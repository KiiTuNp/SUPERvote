#!/usr/bin/env python3
"""
Comprehensive Backend API Testing for Vote Secret Application
Tests all endpoints, database connectivity, WebSocket functionality, and error handling
"""

import requests
import json
import time
import asyncio
import websockets
import tempfile
import os
from datetime import datetime
from typing import Dict, List, Optional

# Configuration
BASE_URL = "https://0d9cde8c-733a-4be6-8f0b-33dc9641dcb8.preview.emergentagent.com/api"
WS_URL = "wss://0d9cde8c-733a-4be6-8f0b-33dc9641dcb8.preview.emergentagent.com/ws"

class VoteSecretTester:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
        self.test_data = {}
        self.results = []
        
    def log_result(self, test_name: str, success: bool, message: str, response_time: float = 0):
        """Log test result"""
        status = "✅ PASS" if success else "❌ FAIL"
        self.results.append({
            'test': test_name,
            'status': status,
            'message': message,
            'response_time': f"{response_time:.3f}s" if response_time > 0 else "N/A"
        })
        print(f"{status} {test_name}: {message} ({response_time:.3f}s)" if response_time > 0 else f"{status} {test_name}: {message}")

    def test_health_check(self):
        """Test health check endpoint"""
        try:
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/health")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'healthy' and 'services' in data:
                    self.log_result("Health Check", True, "Service is healthy", response_time)
                    return True
                else:
                    self.log_result("Health Check", False, f"Unhealthy response: {data}", response_time)
                    return False
            else:
                self.log_result("Health Check", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Health Check", False, f"Connection error: {str(e)}")
            return False

    def test_create_meeting(self):
        """Test meeting creation endpoint"""
        try:
            meeting_data = {
                "title": "Assemblée Générale Extraordinaire 2025",
                "organizer_name": "Marie Dubois"
            }
            
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/meetings", json=meeting_data)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if 'id' in data and 'meeting_code' in data and len(data['meeting_code']) == 8:
                    self.test_data['meeting'] = data
                    self.log_result("Create Meeting", True, f"Meeting created with code: {data['meeting_code']}", response_time)
                    return True
                else:
                    self.log_result("Create Meeting", False, f"Invalid response format: {data}", response_time)
                    return False
            else:
                self.log_result("Create Meeting", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Create Meeting", False, f"Error: {str(e)}")
            return False

    def test_meeting_validation(self):
        """Test meeting creation validation"""
        test_cases = [
            ({"title": "", "organizer_name": "Test"}, "Empty title validation"),
            ({"title": "Test", "organizer_name": ""}, "Empty organizer validation"),
            ({"title": "x" * 201, "organizer_name": "Test"}, "Title length validation"),
            ({"title": "Test", "organizer_name": "x" * 101}, "Organizer length validation")
        ]
        
        all_passed = True
        for invalid_data, test_desc in test_cases:
            try:
                start_time = time.time()
                response = self.session.post(f"{BASE_URL}/meetings", json=invalid_data)
                response_time = time.time() - start_time
                
                if response.status_code == 400:
                    self.log_result(f"Meeting Validation - {test_desc}", True, "Validation error returned correctly", response_time)
                else:
                    self.log_result(f"Meeting Validation - {test_desc}", False, f"Expected 400, got {response.status_code}", response_time)
                    all_passed = False
            except Exception as e:
                self.log_result(f"Meeting Validation - {test_desc}", False, f"Error: {str(e)}")
                all_passed = False
        
        return all_passed

    def test_get_meeting_by_code(self):
        """Test getting meeting by code"""
        if 'meeting' not in self.test_data:
            self.log_result("Get Meeting by Code", False, "No meeting data available")
            return False
            
        try:
            meeting_code = self.test_data['meeting']['meeting_code']
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/meetings/{meeting_code}")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if data['id'] == self.test_data['meeting']['id']:
                    self.log_result("Get Meeting by Code", True, f"Meeting retrieved successfully", response_time)
                    return True
                else:
                    self.log_result("Get Meeting by Code", False, f"Meeting ID mismatch", response_time)
                    return False
            else:
                self.log_result("Get Meeting by Code", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Get Meeting by Code", False, f"Error: {str(e)}")
            return False

    def test_participant_join(self):
        """Test participant joining"""
        if 'meeting' not in self.test_data:
            self.log_result("Participant Join", False, "No meeting data available")
            return False
            
        try:
            join_data = {
                "name": "Pierre Martin",
                "meeting_code": self.test_data['meeting']['meeting_code']
            }
            
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/participants/join", json=join_data)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if 'id' in data and data['name'] == join_data['name']:
                    self.test_data['participant'] = data
                    self.log_result("Participant Join", True, f"Participant joined successfully", response_time)
                    return True
                else:
                    self.log_result("Participant Join", False, f"Invalid response format: {data}", response_time)
                    return False
            else:
                self.log_result("Participant Join", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Participant Join", False, f"Error: {str(e)}")
            return False

    def test_participant_validation(self):
        """Test participant join validation"""
        if 'meeting' not in self.test_data:
            self.log_result("Participant Validation", False, "No meeting data available")
            return False
            
        test_cases = [
            ({"name": "", "meeting_code": self.test_data['meeting']['meeting_code']}, "Empty name validation"),
            ({"name": "Test", "meeting_code": ""}, "Empty meeting code validation"),
            ({"name": "x" * 101, "meeting_code": self.test_data['meeting']['meeting_code']}, "Name length validation"),
            ({"name": "Test", "meeting_code": "INVALID"}, "Invalid meeting code validation"),
            ({"name": "Pierre Martin", "meeting_code": self.test_data['meeting']['meeting_code']}, "Duplicate name validation")
        ]
        
        all_passed = True
        for invalid_data, test_desc in test_cases:
            try:
                start_time = time.time()
                response = self.session.post(f"{BASE_URL}/participants/join", json=invalid_data)
                response_time = time.time() - start_time
                
                if response.status_code == 400 or response.status_code == 404:
                    self.log_result(f"Participant Validation - {test_desc}", True, "Validation error returned correctly", response_time)
                else:
                    self.log_result(f"Participant Validation - {test_desc}", False, f"Expected 400/404, got {response.status_code}", response_time)
                    all_passed = False
            except Exception as e:
                self.log_result(f"Participant Validation - {test_desc}", False, f"Error: {str(e)}")
                all_passed = False
        
        return all_passed

    def test_participant_approval(self):
        """Test participant approval"""
        if 'participant' not in self.test_data:
            self.log_result("Participant Approval", False, "No participant data available")
            return False
            
        try:
            participant_id = self.test_data['participant']['id']
            approval_data = {
                "participant_id": participant_id,
                "approved": True
            }
            
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/participants/{participant_id}/approve", json=approval_data)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'success':
                    self.log_result("Participant Approval", True, "Participant approved successfully", response_time)
                    return True
                else:
                    self.log_result("Participant Approval", False, f"Unexpected response: {data}", response_time)
                    return False
            else:
                self.log_result("Participant Approval", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Participant Approval", False, f"Error: {str(e)}")
            return False

    def test_participant_status(self):
        """Test getting participant status"""
        if 'participant' not in self.test_data:
            self.log_result("Participant Status", False, "No participant data available")
            return False
            
        try:
            participant_id = self.test_data['participant']['id']
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/participants/{participant_id}/status")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if 'status' in data:
                    self.log_result("Participant Status", True, f"Status: {data['status']}", response_time)
                    return True
                else:
                    self.log_result("Participant Status", False, f"Invalid response format: {data}", response_time)
                    return False
            else:
                self.log_result("Participant Status", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Participant Status", False, f"Error: {str(e)}")
            return False

    def test_create_poll(self):
        """Test poll creation"""
        if 'meeting' not in self.test_data:
            self.log_result("Create Poll", False, "No meeting data available")
            return False
            
        try:
            poll_data = {
                "question": "Êtes-vous favorable à l'augmentation du budget de 15% ?",
                "options": ["Oui, je suis favorable", "Non, je m'oppose", "Je m'abstiens"],
                "timer_duration": 300,
                "show_results_real_time": True
            }
            
            meeting_id = self.test_data['meeting']['id']
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/meetings/{meeting_id}/polls", json=poll_data)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if 'id' in data and data['question'] == poll_data['question']:
                    self.test_data['poll'] = data
                    self.log_result("Create Poll", True, f"Poll created successfully", response_time)
                    return True
                else:
                    self.log_result("Create Poll", False, f"Invalid response format: {data}", response_time)
                    return False
            else:
                self.log_result("Create Poll", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Create Poll", False, f"Error: {str(e)}")
            return False

    def test_poll_validation(self):
        """Test poll creation validation"""
        if 'meeting' not in self.test_data:
            self.log_result("Poll Validation", False, "No meeting data available")
            return False
            
        meeting_id = self.test_data['meeting']['id']
        test_cases = [
            ({"question": "", "options": ["A", "B"]}, "Empty question validation"),
            ({"question": "Test?", "options": ["A"]}, "Insufficient options validation"),
            ({"question": "Test?", "options": ["A", ""]}, "Empty option validation"),
            ({"question": "Test?", "options": ["A", "A"]}, "Duplicate options validation")
        ]
        
        all_passed = True
        for invalid_data, test_desc in test_cases:
            try:
                start_time = time.time()
                response = self.session.post(f"{BASE_URL}/meetings/{meeting_id}/polls", json=invalid_data)
                response_time = time.time() - start_time
                
                if response.status_code == 400:
                    self.log_result(f"Poll Validation - {test_desc}", True, "Validation error returned correctly", response_time)
                else:
                    self.log_result(f"Poll Validation - {test_desc}", False, f"Expected 400, got {response.status_code}", response_time)
                    all_passed = False
            except Exception as e:
                self.log_result(f"Poll Validation - {test_desc}", False, f"Error: {str(e)}")
                all_passed = False
        
        return all_passed

    def test_start_poll(self):
        """Test starting a poll"""
        if 'poll' not in self.test_data:
            self.log_result("Start Poll", False, "No poll data available")
            return False
            
        try:
            poll_id = self.test_data['poll']['id']
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/polls/{poll_id}/start")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'started':
                    self.log_result("Start Poll", True, "Poll started successfully", response_time)
                    return True
                else:
                    self.log_result("Start Poll", False, f"Unexpected response: {data}", response_time)
                    return False
            else:
                self.log_result("Start Poll", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Start Poll", False, f"Error: {str(e)}")
            return False

    def test_submit_vote(self):
        """Test vote submission"""
        if 'poll' not in self.test_data:
            self.log_result("Submit Vote", False, "No poll data available")
            return False
            
        try:
            poll = self.test_data['poll']
            option_id = poll['options'][0]['id']  # Vote for first option
            
            vote_data = {
                "poll_id": poll['id'],
                "option_id": option_id
            }
            
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/votes", json=vote_data)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'vote_submitted':
                    self.log_result("Submit Vote", True, "Vote submitted successfully", response_time)
                    return True
                else:
                    self.log_result("Submit Vote", False, f"Unexpected response: {data}", response_time)
                    return False
            else:
                self.log_result("Submit Vote", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Submit Vote", False, f"Error: {str(e)}")
            return False

    def test_poll_results(self):
        """Test getting poll results"""
        if 'poll' not in self.test_data:
            self.log_result("Poll Results", False, "No poll data available")
            return False
            
        try:
            poll_id = self.test_data['poll']['id']
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/polls/{poll_id}/results")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if 'question' in data and 'results' in data and 'total_votes' in data:
                    self.log_result("Poll Results", True, f"Results retrieved, total votes: {data['total_votes']}", response_time)
                    return True
                else:
                    self.log_result("Poll Results", False, f"Invalid response format: {data}", response_time)
                    return False
            else:
                self.log_result("Poll Results", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Poll Results", False, f"Error: {str(e)}")
            return False

    def test_close_poll(self):
        """Test closing a poll"""
        if 'poll' not in self.test_data:
            self.log_result("Close Poll", False, "No poll data available")
            return False
            
        try:
            poll_id = self.test_data['poll']['id']
            start_time = time.time()
            response = self.session.post(f"{BASE_URL}/polls/{poll_id}/close")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'closed':
                    self.log_result("Close Poll", True, "Poll closed successfully", response_time)
                    return True
                else:
                    self.log_result("Close Poll", False, f"Unexpected response: {data}", response_time)
                    return False
            else:
                self.log_result("Close Poll", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Close Poll", False, f"Error: {str(e)}")
            return False

    def test_get_meeting_polls(self):
        """Test getting all polls for a meeting"""
        if 'meeting' not in self.test_data:
            self.log_result("Get Meeting Polls", False, "No meeting data available")
            return False
            
        try:
            meeting_id = self.test_data['meeting']['id']
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/meetings/{meeting_id}/polls")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if isinstance(data, list) and len(data) > 0:
                    self.log_result("Get Meeting Polls", True, f"Retrieved {len(data)} polls", response_time)
                    return True
                else:
                    self.log_result("Get Meeting Polls", True, "No polls found (valid response)", response_time)
                    return True
            else:
                self.log_result("Get Meeting Polls", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Get Meeting Polls", False, f"Error: {str(e)}")
            return False

    def test_organizer_view(self):
        """Test organizer view endpoint"""
        if 'meeting' not in self.test_data:
            self.log_result("Organizer View", False, "No meeting data available")
            return False
            
        try:
            meeting_id = self.test_data['meeting']['id']
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/meetings/{meeting_id}/organizer")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                if 'meeting' in data and 'participants' in data and 'polls' in data:
                    self.log_result("Organizer View", True, f"Organizer view retrieved successfully", response_time)
                    return True
                else:
                    self.log_result("Organizer View", False, f"Invalid response format: {data}", response_time)
                    return False
            else:
                self.log_result("Organizer View", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("Organizer View", False, f"Error: {str(e)}")
            return False

    def test_pdf_report_generation(self):
        """Test PDF report generation"""
        if 'meeting' not in self.test_data:
            self.log_result("PDF Report Generation", False, "No meeting data available")
            return False
            
        try:
            meeting_id = self.test_data['meeting']['id']
            start_time = time.time()
            response = self.session.get(f"{BASE_URL}/meetings/{meeting_id}/report")
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                # Check if response is PDF
                content_type = response.headers.get('content-type', '')
                if 'application/pdf' in content_type:
                    # Save PDF to temporary file to verify it's valid
                    with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as tmp_file:
                        tmp_file.write(response.content)
                        tmp_path = tmp_file.name
                    
                    # Check file size
                    file_size = os.path.getsize(tmp_path)
                    os.unlink(tmp_path)  # Clean up
                    
                    if file_size > 1000:  # PDF should be at least 1KB
                        self.log_result("PDF Report Generation", True, f"PDF generated successfully ({file_size} bytes)", response_time)
                        return True
                    else:
                        self.log_result("PDF Report Generation", False, f"PDF too small ({file_size} bytes)", response_time)
                        return False
                else:
                    self.log_result("PDF Report Generation", False, f"Wrong content type: {content_type}", response_time)
                    return False
            else:
                self.log_result("PDF Report Generation", False, f"HTTP {response.status_code}: {response.text}", response_time)
                return False
        except Exception as e:
            self.log_result("PDF Report Generation", False, f"Error: {str(e)}")
            return False

    async def test_websocket_connection(self):
        """Test WebSocket connection"""
        if 'meeting' not in self.test_data:
            self.log_result("WebSocket Connection", False, "No meeting data available")
            return False
            
        try:
            meeting_id = self.test_data['meeting']['id']
            ws_url = f"{WS_URL}/meetings/{meeting_id}"
            
            start_time = time.time()
            async with websockets.connect(ws_url) as websocket:
                # Send a test message
                await websocket.send("test message")
                
                # Try to receive (with timeout)
                try:
                    response = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                    response_time = time.time() - start_time
                    self.log_result("WebSocket Connection", True, "WebSocket connection successful", response_time)
                    return True
                except asyncio.TimeoutError:
                    response_time = time.time() - start_time
                    self.log_result("WebSocket Connection", True, "WebSocket connected (no immediate response)", response_time)
                    return True
                    
        except Exception as e:
            self.log_result("WebSocket Connection", False, f"WebSocket error: {str(e)}")
            return False

    def test_cors_headers(self):
        """Test CORS configuration"""
        try:
            start_time = time.time()
            response = self.session.options(f"{BASE_URL}/health", headers={
                'Origin': 'https://example.com',
                'Access-Control-Request-Method': 'GET'
            })
            response_time = time.time() - start_time
            
            cors_headers = {
                'Access-Control-Allow-Origin': response.headers.get('Access-Control-Allow-Origin'),
                'Access-Control-Allow-Methods': response.headers.get('Access-Control-Allow-Methods'),
                'Access-Control-Allow-Headers': response.headers.get('Access-Control-Allow-Headers')
            }
            
            if any(cors_headers.values()):
                self.log_result("CORS Configuration", True, f"CORS headers present", response_time)
                return True
            else:
                self.log_result("CORS Configuration", False, "No CORS headers found", response_time)
                return False
                
        except Exception as e:
            self.log_result("CORS Configuration", False, f"Error: {str(e)}")
            return False

    def test_performance_load(self):
        """Test basic performance with multiple requests"""
        try:
            # Test multiple health check requests
            times = []
            for i in range(5):
                start_time = time.time()
                response = self.session.get(f"{BASE_URL}/health")
                response_time = time.time() - start_time
                times.append(response_time)
                
                if response.status_code != 200:
                    self.log_result("Performance Load Test", False, f"Request {i+1} failed with status {response.status_code}")
                    return False
            
            avg_time = sum(times) / len(times)
            max_time = max(times)
            
            if avg_time < 2.0 and max_time < 5.0:  # Reasonable thresholds
                self.log_result("Performance Load Test", True, f"Avg: {avg_time:.3f}s, Max: {max_time:.3f}s")
                return True
            else:
                self.log_result("Performance Load Test", False, f"Slow response - Avg: {avg_time:.3f}s, Max: {max_time:.3f}s")
                return False
                
        except Exception as e:
            self.log_result("Performance Load Test", False, f"Error: {str(e)}")
            return False

    def test_error_handling(self):
        """Test error handling for non-existent resources"""
        test_cases = [
            (f"{BASE_URL}/meetings/INVALID", "Invalid meeting code"),
            (f"{BASE_URL}/participants/invalid-id/status", "Invalid participant ID"),
            (f"{BASE_URL}/polls/invalid-id/results", "Invalid poll ID"),
            (f"{BASE_URL}/meetings/invalid-id/report", "Invalid meeting ID for report")
        ]
        
        all_passed = True
        for url, test_desc in test_cases:
            try:
                start_time = time.time()
                response = self.session.get(url)
                response_time = time.time() - start_time
                
                if response.status_code == 404:
                    self.log_result(f"Error Handling - {test_desc}", True, "404 returned correctly", response_time)
                else:
                    self.log_result(f"Error Handling - {test_desc}", False, f"Expected 404, got {response.status_code}", response_time)
                    all_passed = False
            except Exception as e:
                self.log_result(f"Error Handling - {test_desc}", False, f"Error: {str(e)}")
                all_passed = False
        
        return all_passed

    def run_all_tests(self):
        """Run all backend tests"""
        print("🚀 Starting Vote Secret Backend API Tests")
        print("=" * 60)
        
        # Core functionality tests
        tests = [
            ("Health Check", self.test_health_check),
            ("Create Meeting", self.test_create_meeting),
            ("Meeting Validation", self.test_meeting_validation),
            ("Get Meeting by Code", self.test_get_meeting_by_code),
            ("Participant Join", self.test_participant_join),
            ("Participant Validation", self.test_participant_validation),
            ("Participant Approval", self.test_participant_approval),
            ("Participant Status", self.test_participant_status),
            ("Create Poll", self.test_create_poll),
            ("Poll Validation", self.test_poll_validation),
            ("Start Poll", self.test_start_poll),
            ("Submit Vote", self.test_submit_vote),
            ("Poll Results", self.test_poll_results),
            ("Close Poll", self.test_close_poll),
            ("Get Meeting Polls", self.test_get_meeting_polls),
            ("Organizer View", self.test_organizer_view),
            ("PDF Report Generation", self.test_pdf_report_generation),
            ("CORS Configuration", self.test_cors_headers),
            ("Performance Load Test", self.test_performance_load),
            ("Error Handling", self.test_error_handling)
        ]
        
        passed = 0
        total = len(tests)
        
        for test_name, test_func in tests:
            try:
                if test_func():
                    passed += 1
            except Exception as e:
                self.log_result(test_name, False, f"Test execution error: {str(e)}")
        
        # WebSocket test (async)
        try:
            ws_result = asyncio.run(self.test_websocket_connection())
            if ws_result:
                passed += 1
            total += 1
        except Exception as e:
            self.log_result("WebSocket Connection", False, f"WebSocket test error: {str(e)}")
            total += 1
        
        print("\n" + "=" * 60)
        print(f"🏁 Test Results: {passed}/{total} tests passed")
        
        if passed == total:
            print("🎉 All tests passed! Backend is production ready.")
        else:
            print(f"⚠️  {total - passed} tests failed. Review issues above.")
        
        return passed, total, self.results

def main():
    """Main test execution"""
    tester = VoteSecretTester()
    passed, total, results = tester.run_all_tests()
    
    # Print summary
    print("\n📊 DETAILED TEST SUMMARY")
    print("=" * 60)
    
    for result in results:
        print(f"{result['status']} {result['test']}")
        if result['message']:
            print(f"    └─ {result['message']}")
        if result['response_time'] != "N/A":
            print(f"    └─ Response time: {result['response_time']}")
    
    return passed == total

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)