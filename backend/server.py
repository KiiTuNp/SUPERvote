from fastapi import FastAPI, APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
import asyncio
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
from pathlib import Path
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime
from enum import Enum
import json
import tempfile
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT

# Global lock for vote operations
vote_locks = {}
lock_manager = asyncio.Lock()

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ['DB_NAME']]

# Create the main app without a prefix
app = FastAPI()

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")

# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, meeting_id: str):
        await websocket.accept()
        if meeting_id not in self.active_connections:
            self.active_connections[meeting_id] = []
        self.active_connections[meeting_id].append(websocket)

    def disconnect(self, websocket: WebSocket, meeting_id: str):
        if meeting_id in self.active_connections:
            self.active_connections[meeting_id].remove(websocket)

    async def send_to_meeting(self, message: dict, meeting_id: str):
        if meeting_id in self.active_connections:
            for connection in self.active_connections[meeting_id]:
                try:
                    await connection.send_text(json.dumps(message))
                except:
                    pass

manager = ConnectionManager()

# Enums
class ParticipantStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved" 
    REJECTED = "rejected"

class PollStatus(str, Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    CLOSED = "closed"

class MeetingStatus(str, Enum):
    ACTIVE = "active"
    COMPLETED = "completed"

# Models
class Meeting(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    organizer_name: str
    meeting_code: str = Field(default_factory=lambda: str(uuid.uuid4())[:8].upper())
    status: MeetingStatus = MeetingStatus.ACTIVE
    created_at: datetime = Field(default_factory=datetime.utcnow)

class MeetingCreate(BaseModel):
    title: str
    organizer_name: str

class Participant(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    meeting_id: str
    approval_status: ParticipantStatus = ParticipantStatus.PENDING
    joined_at: datetime = Field(default_factory=datetime.utcnow)

class ParticipantJoin(BaseModel):
    name: str
    meeting_code: str

class ParticipantApproval(BaseModel):
    participant_id: str
    approved: bool

class PollOption(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    text: str
    votes: int = 0

class Poll(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    meeting_id: str
    question: str
    options: List[PollOption]
    status: PollStatus = PollStatus.DRAFT
    timer_duration: Optional[int] = None  # in seconds
    timer_started_at: Optional[datetime] = None
    show_results_real_time: bool = True  # New field for controlling result visibility
    created_at: datetime = Field(default_factory=datetime.utcnow)

class PollCreate(BaseModel):
    question: str
    options: List[str]
    timer_duration: Optional[int] = None
    show_results_real_time: bool = True  # New field

class Vote(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    poll_id: str
    option_id: str
    voted_at: datetime = Field(default_factory=datetime.utcnow)
    # Note: No participant_id to maintain anonymity

class VoteCreate(BaseModel):
    poll_id: str
    option_id: str

# Meeting endpoints
@api_router.post("/meetings", response_model=Meeting)
async def create_meeting(meeting_data: MeetingCreate):
    # Validation des champs obligatoires
    if not meeting_data.title or not meeting_data.title.strip():
        raise HTTPException(status_code=400, detail="Le titre de la réunion est requis")
    if not meeting_data.organizer_name or not meeting_data.organizer_name.strip():
        raise HTTPException(status_code=400, detail="Le nom de l'organisateur est requis")
    
    # Limitation de la longueur des champs
    if len(meeting_data.title.strip()) > 200:
        raise HTTPException(status_code=400, detail="Le titre de la réunion ne peut pas dépasser 200 caractères")
    if len(meeting_data.organizer_name.strip()) > 100:
        raise HTTPException(status_code=400, detail="Le nom de l'organisateur ne peut pas dépasser 100 caractères")
    
    meeting = Meeting(
        title=meeting_data.title.strip(),
        organizer_name=meeting_data.organizer_name.strip()
    )
    await db.meetings.insert_one(meeting.dict())
    return meeting

@api_router.get("/meetings/{meeting_code}")
async def get_meeting_by_code(meeting_code: str):
    meeting = await db.meetings.find_one({"meeting_code": meeting_code, "status": "active"})
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return Meeting(**meeting)

@api_router.get("/meetings/{meeting_id}/organizer")
async def get_meeting_organizer_view(meeting_id: str):
    meeting = await db.meetings.find_one({"id": meeting_id})
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    
    # Get participants
    participants = await db.participants.find({"meeting_id": meeting_id}).to_list(1000)
    
    # Get polls
    polls = await db.polls.find({"meeting_id": meeting_id}).to_list(1000)
    
    return {
        "meeting": Meeting(**meeting),
        "participants": [Participant(**p) for p in participants],
        "polls": [Poll(**poll) for poll in polls]
    }

# Participant endpoints
@api_router.post("/participants/join")
async def join_meeting(join_data: ParticipantJoin):
    # Validation des champs obligatoires
    if not join_data.name or not join_data.name.strip():
        raise HTTPException(status_code=400, detail="Le nom du participant est requis")
    if not join_data.meeting_code or not join_data.meeting_code.strip():
        raise HTTPException(status_code=400, detail="Le code de réunion est requis")
    
    # Limitation de la longueur et format
    if len(join_data.name.strip()) > 100:
        raise HTTPException(status_code=400, detail="Le nom ne peut pas dépasser 100 caractères")
    if len(join_data.meeting_code.strip()) != 8:
        raise HTTPException(status_code=400, detail="Le code de réunion doit faire 8 caractères")
    
    clean_name = join_data.name.strip()
    clean_code = join_data.meeting_code.strip().upper()
    
    # Check if meeting exists and is active
    meeting = await db.meetings.find_one({"meeting_code": clean_code, "status": "active"})
    if not meeting:
        raise HTTPException(status_code=404, detail="Réunion non trouvée ou inactive")
    
    # Check if participant name already exists in this meeting
    existing = await db.participants.find_one({
        "name": clean_name, 
        "meeting_id": meeting["id"]
    })
    if existing:
        raise HTTPException(status_code=400, detail="Ce nom est déjà pris dans cette réunion")
    
    participant = Participant(name=clean_name, meeting_id=meeting["id"])
    await db.participants.insert_one(participant.dict())
    
    # Notify organizer via WebSocket
    await manager.send_to_meeting({
        "type": "participant_joined",
        "participant": participant.dict()
    }, meeting["id"])
    
    return participant

@api_router.post("/participants/{participant_id}/approve")
async def approve_participant(participant_id: str, approval: ParticipantApproval):
    participant = await db.participants.find_one({"id": participant_id})
    if not participant:
        raise HTTPException(status_code=404, detail="Participant not found")
    
    new_status = ParticipantStatus.APPROVED if approval.approved else ParticipantStatus.REJECTED
    await db.participants.update_one(
        {"id": participant_id},
        {"$set": {"approval_status": new_status}}
    )
    
    # Notify via WebSocket
    await manager.send_to_meeting({
        "type": "participant_approved",
        "participant_id": participant_id,
        "status": new_status
    }, participant["meeting_id"])
    
    return {"status": "success"}

@api_router.get("/participants/{participant_id}/status")
async def get_participant_status(participant_id: str):
    participant = await db.participants.find_one({"id": participant_id})
    if not participant:
        raise HTTPException(status_code=404, detail="Participant not found")
    return {"status": participant["approval_status"]}

# Poll endpoints
@api_router.post("/meetings/{meeting_id}/polls", response_model=Poll)
async def create_poll(meeting_id: str, poll_data: PollCreate):
    # Validation des champs obligatoires
    if not poll_data.question or not poll_data.question.strip():
        raise HTTPException(status_code=400, detail="La question du sondage est requise")
    if not poll_data.options or len(poll_data.options) < 2:
        raise HTTPException(status_code=400, detail="Au moins 2 options sont requises")
    
    # Validation des options
    clean_options = []
    for i, option in enumerate(poll_data.options):
        if not option or not option.strip():
            raise HTTPException(status_code=400, detail=f"L'option {i+1} ne peut pas être vide")
        if len(option.strip()) > 200:
            raise HTTPException(status_code=400, detail=f"L'option {i+1} ne peut pas dépasser 200 caractères")
        clean_options.append(option.strip())
    
    # Limitation du nombre d'options
    if len(clean_options) > 20:
        raise HTTPException(status_code=400, detail="Maximum 20 options par sondage")
    
    # Vérifier les doublons
    if len(set(clean_options)) != len(clean_options):
        raise HTTPException(status_code=400, detail="Les options doivent être uniques")
    
    # Verify meeting exists
    meeting = await db.meetings.find_one({"id": meeting_id})
    if not meeting:
        raise HTTPException(status_code=404, detail="Réunion non trouvée")
    
    options = [PollOption(text=opt) for opt in clean_options]
    poll = Poll(
        meeting_id=meeting_id,
        question=poll_data.question.strip(),
        options=options,
        timer_duration=poll_data.timer_duration,
        show_results_real_time=poll_data.show_results_real_time
    )
    
    await db.polls.insert_one(poll.dict())
    return poll

@api_router.post("/polls/{poll_id}/start")
async def start_poll(poll_id: str):
    poll = await db.polls.find_one({"id": poll_id})
    if not poll:
        raise HTTPException(status_code=404, detail="Poll not found")
    
    update_data = {
        "status": PollStatus.ACTIVE,
        "timer_started_at": datetime.utcnow() if poll.get("timer_duration") else None
    }
    
    await db.polls.update_one({"id": poll_id}, {"$set": update_data})
    
    # Notify participants
    await manager.send_to_meeting({
        "type": "poll_started",
        "poll_id": poll_id
    }, poll["meeting_id"])
    
    return {"status": "started"}

@api_router.post("/polls/{poll_id}/close")
async def close_poll(poll_id: str):
    poll = await db.polls.find_one({"id": poll_id})
    if not poll:
        raise HTTPException(status_code=404, detail="Poll not found")
    
    await db.polls.update_one({"id": poll_id}, {"$set": {"status": PollStatus.CLOSED}})
    
    # Notify participants
    await manager.send_to_meeting({
        "type": "poll_closed",
        "poll_id": poll_id
    }, poll["meeting_id"])
    
    return {"status": "closed"}

@api_router.get("/meetings/{meeting_id}/polls")
async def get_meeting_polls(meeting_id: str):
    polls = await db.polls.find({"meeting_id": meeting_id}).to_list(1000)
    return [Poll(**poll) for poll in polls]

# Voting endpoints
@api_router.post("/votes")
async def submit_vote(vote_data: VoteCreate):
    # Get or create lock for this poll
    async with lock_manager:
        if vote_data.poll_id not in vote_locks:
            vote_locks[vote_data.poll_id] = asyncio.Lock()
        poll_lock = vote_locks[vote_data.poll_id]
    
    # Use lock to prevent concurrent vote updates
    async with poll_lock:
        # Verify poll exists and is active
        poll = await db.polls.find_one({"id": vote_data.poll_id})
        if not poll:
            raise HTTPException(status_code=404, detail="Sondage non trouvé")
        
        if poll["status"] != PollStatus.ACTIVE:
            raise HTTPException(status_code=400, detail="Le sondage n'est pas actif")
        
        # Check if option exists
        option_exists = any(opt["id"] == vote_data.option_id for opt in poll["options"])
        if not option_exists:
            raise HTTPException(status_code=400, detail="Option invalide")
        
        # Create anonymous vote
        vote = Vote(poll_id=vote_data.poll_id, option_id=vote_data.option_id)
        await db.votes.insert_one(vote.dict())
        
        # Update poll results immediately in the same transaction
        await update_poll_results(vote_data.poll_id)
        
        # Notify real-time updates
        updated_poll = await db.polls.find_one({"id": vote_data.poll_id})
        await manager.send_to_meeting({
            "type": "vote_submitted",
            "poll": Poll(**updated_poll).dict()
        }, poll["meeting_id"])
        
        return {"status": "vote_submitted", "message": "Vote enregistré avec succès"}

async def update_poll_results(poll_id: str):
    # Get all votes for this poll
    votes = await db.votes.find({"poll_id": poll_id}).to_list(1000)
    vote_counts = {}
    
    for vote in votes:
        option_id = vote["option_id"]
        vote_counts[option_id] = vote_counts.get(option_id, 0) + 1
    
    # Update poll options with vote counts
    poll = await db.polls.find_one({"id": poll_id})
    if poll:
        for option in poll["options"]:
            option["votes"] = vote_counts.get(option["id"], 0)
        
        await db.polls.update_one(
            {"id": poll_id},
            {"$set": {"options": poll["options"]}}
        )

@api_router.get("/polls/{poll_id}/results")
async def get_poll_results(poll_id: str):
    poll = await db.polls.find_one({"id": poll_id})
    if not poll:
        raise HTTPException(status_code=404, detail="Poll not found")
    
    await update_poll_results(poll_id)
    updated_poll = await db.polls.find_one({"id": poll_id})
    
    total_votes = sum(opt["votes"] for opt in updated_poll["options"])
    
    results = []
    for option in updated_poll["options"]:
        percentage = (option["votes"] / total_votes * 100) if total_votes > 0 else 0
        results.append({
            "option": option["text"],
            "votes": option["votes"],
            "percentage": round(percentage, 1)
        })
    
    return {
        "question": updated_poll["question"],
        "results": results,
        "total_votes": total_votes
    }

def generate_pdf_report(meeting_data, participants_data, polls_data):
    """Generate PDF report for the meeting"""
    
    # Create temporary file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    temp_path = temp_file.name
    temp_file.close()
    
    # Create PDF document
    doc = SimpleDocTemplate(temp_path, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []
    
    # Title style
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=colors.HexColor('#1e40af'),
        alignment=TA_CENTER,
        spaceAfter=30
    )
    
    # Subtitle style
    subtitle_style = ParagraphStyle(
        'CustomSubtitle',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=colors.HexColor('#374151'),
        spaceAfter=20
    )
    
    # Add title
    story.append(Paragraph("RAPPORT DE VOTE SECRET", title_style))
    story.append(Spacer(1, 20))
    
    # Meeting info
    story.append(Paragraph(f"<b>Réunion:</b> {meeting_data['title']}", styles['Normal']))
    story.append(Paragraph(f"<b>Organisateur:</b> {meeting_data['organizer_name']}", styles['Normal']))
    story.append(Paragraph(f"<b>Code de réunion:</b> {meeting_data['meeting_code']}", styles['Normal']))
    story.append(Paragraph(f"<b>Date de génération:</b> {datetime.now().strftime('%d/%m/%Y à %H:%M')}", styles['Normal']))
    story.append(Spacer(1, 30))
    
    # Participants section
    story.append(Paragraph("PARTICIPANTS APPROUVÉS", subtitle_style))
    
    # Create participants table
    approved_participants = [p for p in participants_data if p['approval_status'] == 'approved']
    
    if approved_participants:
        participants_table_data = [['#', 'Nom', 'Heure de participation']]
        for i, participant in enumerate(approved_participants, 1):
            # Handle both datetime objects and ISO strings
            if isinstance(participant['joined_at'], str):
                joined_time = datetime.fromisoformat(participant['joined_at'].replace('Z', '+00:00')).strftime('%H:%M')
            else:
                joined_time = participant['joined_at'].strftime('%H:%M')
            participants_table_data.append([str(i), participant['name'], joined_time])
        
        participants_table = Table(participants_table_data, colWidths=[0.5*inch, 3*inch, 1.5*inch])
        participants_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#f3f4f6')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.black),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 12),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -1), colors.white),
            ('GRID', (0, 0), (-1, -1), 1, colors.black),
            ('FONTSIZE', (0, 1), (-1, -1), 10),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ]))
        story.append(participants_table)
        story.append(Paragraph(f"<b>Total des participants approuvés:</b> {len(approved_participants)}", styles['Normal']))
    else:
        story.append(Paragraph("Aucun participant approuvé", styles['Normal']))
    
    story.append(Spacer(1, 30))
    
    # Polls section
    story.append(Paragraph("RÉSULTATS DES SONDAGES", subtitle_style))
    
    if polls_data:
        for i, poll in enumerate(polls_data, 1):
            # Poll question
            story.append(Paragraph(f"<b>Sondage {i}:</b> {poll['question']}", styles['Heading3']))
            story.append(Spacer(1, 10))
            
            # Calculate total votes
            total_votes = sum(opt['votes'] for opt in poll['options'])
            
            if total_votes > 0:
                # Create results table
                results_data = [['Option', 'Votes', 'Pourcentage']]
                for option in poll['options']:
                    percentage = (option['votes'] / total_votes * 100) if total_votes > 0 else 0
                    results_data.append([
                        option['text'],
                        str(option['votes']),
                        f"{percentage:.1f}%"
                    ])
                
                # Add total row
                results_data.append(['TOTAL', str(total_votes), '100.0%'])
                
                results_table = Table(results_data, colWidths=[3*inch, 1*inch, 1*inch])
                results_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#f3f4f6')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.black),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('ALIGN', (1, 0), (-1, -1), 'CENTER'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 11),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                    ('BACKGROUND', (0, 1), (-1, -2), colors.white),
                    ('BACKGROUND', (0, -1), (-1, -1), colors.HexColor('#e5e7eb')),
                    ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
                    ('GRID', (0, 0), (-1, -1), 1, colors.black),
                    ('FONTSIZE', (0, 1), (-1, -1), 10),
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ]))
                story.append(results_table)
            else:
                story.append(Paragraph("Aucun vote enregistré pour ce sondage", styles['Normal']))
            
            story.append(Spacer(1, 20))
    else:
        story.append(Paragraph("Aucun sondage n'a été créé lors de cette réunion", styles['Normal']))
    
    # Footer
    story.append(Spacer(1, 50))
    footer_style = ParagraphStyle(
        'Footer',
        parent=styles['Normal'],
        fontSize=9,
        textColor=colors.grey,
        alignment=TA_CENTER
    )
    story.append(Paragraph("Rapport généré par le système Vote Secret", footer_style))
    story.append(Paragraph("Toutes les données de cette réunion ont été supprimées après génération de ce rapport", footer_style))
    
    # Build PDF
    doc.build(story)
    
    return temp_path

@api_router.get("/meetings/{meeting_id}/report")
async def generate_meeting_report(meeting_id: str):
    """Generate and download PDF report, then delete all meeting data"""
    
    # Get meeting data
    meeting = await db.meetings.find_one({"id": meeting_id})
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    
    # Get participants data
    participants = await db.participants.find({"meeting_id": meeting_id}).to_list(1000)
    
    # Get polls data with updated results
    polls = await db.polls.find({"meeting_id": meeting_id}).to_list(1000)
    
    # Update all poll results before generating report
    for poll in polls:
        await update_poll_results(poll["id"])
    
    # Get updated polls with final results
    updated_polls = await db.polls.find({"meeting_id": meeting_id}).to_list(1000)
    
    try:
        # Generate PDF
        pdf_path = generate_pdf_report(meeting, participants, updated_polls)
        
        # Create filename
        safe_title = "".join(c for c in meeting['title'] if c.isalnum() or c in (' ', '-', '_')).rstrip()
        filename = f"Rapport_{safe_title}_{meeting['meeting_code']}.pdf"
        
        # Mark meeting as completed BEFORE deletion (for logging purposes)
        await db.meetings.update_one(
            {"id": meeting_id},
            {"$set": {"status": MeetingStatus.COMPLETED, "completed_at": datetime.utcnow()}}
        )
        
        # Delete all associated data after PDF generation
        # Delete votes first (they reference polls)
        poll_ids = [poll["id"] for poll in updated_polls]
        if poll_ids:
            delete_votes_result = await db.votes.delete_many({"poll_id": {"$in": poll_ids}})
            logger.info(f"Deleted {delete_votes_result.deleted_count} votes for meeting {meeting_id}")
        
        # Delete polls
        delete_polls_result = await db.polls.delete_many({"meeting_id": meeting_id})
        logger.info(f"Deleted {delete_polls_result.deleted_count} polls for meeting {meeting_id}")
        
        # Delete participants
        delete_participants_result = await db.participants.delete_many({"meeting_id": meeting_id})
        logger.info(f"Deleted {delete_participants_result.deleted_count} participants for meeting {meeting_id}")
        
        # Finally delete the meeting itself
        delete_meeting_result = await db.meetings.delete_one({"id": meeting_id})
        logger.info(f"Deleted meeting {meeting_id}")
        
        logger.info(f"Complete data cleanup finished for meeting {meeting_id}")
        
        # Return the PDF file
        return FileResponse(
            path=pdf_path,
            filename=filename,
            media_type='application/pdf',
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
        
    except Exception as e:
        logger.error(f"Error generating report for meeting {meeting_id}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error generating report: {str(e)}")

# WebSocket endpoint
@app.websocket("/ws/meetings/{meeting_id}")
async def websocket_endpoint(websocket: WebSocket, meeting_id: str):
    await manager.connect(websocket, meeting_id)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket, meeting_id)

# Health check endpoint for production
@app.get("/api/health")
async def health_check():
    """Health check endpoint for load balancers and monitoring"""
    try:
        # Test database connection
        await client.admin.command('ping')
        return {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "services": {
                "database": "connected",
                "api": "running"
            }
        }
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        raise HTTPException(status_code=503, detail="Service unhealthy")

# Include the router in the main app
app.include_router(api_router)

# CORS configuration - restrict in production
cors_origins = os.environ.get('CORS_ORIGINS', '*').split(',')
app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=cors_origins,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()