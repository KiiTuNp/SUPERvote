// MongoDB initialization script for production
db = db.getSiblingDB('vote_secret_db');

// Create application user
db.createUser({
  user: 'voteuser',
  pwd: process.env.MONGO_USER_PASSWORD,
  roles: [
    {
      role: 'readWrite',
      db: 'vote_secret_db'
    }
  ]
});

// Create collections with proper indexes
db.meetings.createIndex({ "meeting_code": 1 }, { unique: true });
db.meetings.createIndex({ "id": 1 }, { unique: true });
db.meetings.createIndex({ "status": 1 });
db.meetings.createIndex({ "created_at": 1 });

db.participants.createIndex({ "id": 1 }, { unique: true });
db.participants.createIndex({ "meeting_id": 1 });
db.participants.createIndex({ "approval_status": 1 });
db.participants.createIndex({ "meeting_id": 1, "name": 1 }, { unique: true });

db.polls.createIndex({ "id": 1 }, { unique: true });
db.polls.createIndex({ "meeting_id": 1 });
db.polls.createIndex({ "status": 1 });

db.votes.createIndex({ "id": 1 }, { unique: true });
db.votes.createIndex({ "poll_id": 1 });
db.votes.createIndex({ "voted_at": 1 });

print('Database initialization completed successfully');