#!/usr/bin/env python3
"""
Basic Backend Functionality Test for SUPERvote Application
Tests the core backend functionality as requested in the review.
"""

import requests
import json
import sys
import time
from datetime import datetime

class BasicBackendTester:
    def __init__(self, base_url="https://33908b3d-6a6e-4ef3-bc46-8d32783a6199.preview.emergentagent.com"):
        self.base_url = base_url
        self.tests_run = 0
        self.tests_passed = 0
        self.room_id = None
        self.participant_token = None
        self.participant_id = None
        self.poll_id = None
        self.organizer_name = f"TestOrg_{datetime.now().strftime('%H%M%S')}"

    def log_test(self, name, success, details=""):
        """Log test results"""
        self.tests_run += 1
        if success:
            self.tests_passed += 1
            print(f"✅ {name}")
            if details:
                print(f"   {details}")
        else:
            print(f"❌ {name}")
            if details:
                print(f"   {details}")

    def test_backend_server_accessible(self):
        """Test 1: Check if backend server is running and accessible"""
        try:
            response = requests.get(f"{self.base_url}/api/health", timeout=10)
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'healthy':
                    self.log_test("Backend Server Accessible", True, f"Health check returned: {data}")
                    return True
                else:
                    self.log_test("Backend Server Accessible", False, f"Unexpected health response: {data}")
                    return False
            else:
                self.log_test("Backend Server Accessible", False, f"Health check failed with status: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Backend Server Accessible", False, f"Connection error: {str(e)}")
            return False

    def test_health_endpoint(self):
        """Test 2: Test the health endpoint (/api/health)"""
        try:
            response = requests.get(f"{self.base_url}/api/health")
            if response.status_code == 200:
                data = response.json()
                expected_keys = ['status']
                if all(key in data for key in expected_keys):
                    self.log_test("Health Endpoint", True, f"Response: {data}")
                    return True
                else:
                    self.log_test("Health Endpoint", False, f"Missing expected keys in response: {data}")
                    return False
            else:
                self.log_test("Health Endpoint", False, f"Status code: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Health Endpoint", False, f"Error: {str(e)}")
            return False

    def test_room_creation_endpoint(self):
        """Test 3: Test room creation endpoint"""
        try:
            params = {"organizer_name": self.organizer_name}
            response = requests.post(f"{self.base_url}/api/rooms/create", params=params)
            
            if response.status_code == 200:
                data = response.json()
                if 'room_id' in data and 'organizer_name' in data:
                    self.room_id = data['room_id']
                    self.log_test("Room Creation Endpoint", True, f"Created room: {self.room_id}")
                    return True
                else:
                    self.log_test("Room Creation Endpoint", False, f"Missing required fields: {data}")
                    return False
            else:
                self.log_test("Room Creation Endpoint", False, f"Status code: {response.status_code}, Response: {response.text}")
                return False
        except Exception as e:
            self.log_test("Room Creation Endpoint", False, f"Error: {str(e)}")
            return False

    def test_room_join_endpoint(self):
        """Test 4: Test room join endpoint"""
        if not self.room_id:
            self.log_test("Room Join Endpoint", False, "No room ID available")
            return False
            
        try:
            params = {"room_id": self.room_id, "participant_name": "TestParticipant"}
            response = requests.post(f"{self.base_url}/api/rooms/join", params=params)
            
            if response.status_code == 200:
                data = response.json()
                required_fields = ['participant_token', 'participant_name', 'room_id', 'approval_status']
                if all(field in data for field in required_fields):
                    self.participant_token = data['participant_token']
                    self.log_test("Room Join Endpoint", True, f"Participant joined with status: {data['approval_status']}")
                    return True
                else:
                    self.log_test("Room Join Endpoint", False, f"Missing required fields: {data}")
                    return False
            else:
                self.log_test("Room Join Endpoint", False, f"Status code: {response.status_code}, Response: {response.text}")
                return False
        except Exception as e:
            self.log_test("Room Join Endpoint", False, f"Error: {str(e)}")
            return False

    def test_room_status_endpoint(self):
        """Test 5: Test room status endpoint"""
        if not self.room_id:
            self.log_test("Room Status Endpoint", False, "No room ID available")
            return False
            
        try:
            response = requests.get(f"{self.base_url}/api/rooms/{self.room_id}/status")
            
            if response.status_code == 200:
                data = response.json()
                required_fields = ['room_id', 'organizer_name', 'participant_count', 'approved_count', 'pending_count']
                if all(field in data for field in required_fields):
                    self.log_test("Room Status Endpoint", True, f"Status: {data['participant_count']} participants, {data['pending_count']} pending")
                    return True
                else:
                    self.log_test("Room Status Endpoint", False, f"Missing required fields: {data}")
                    return False
            else:
                self.log_test("Room Status Endpoint", False, f"Status code: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Room Status Endpoint", False, f"Error: {str(e)}")
            return False

    def test_participants_list_endpoint(self):
        """Test 6: Test participants list endpoint"""
        if not self.room_id:
            self.log_test("Participants List Endpoint", False, "No room ID available")
            return False
            
        try:
            response = requests.get(f"{self.base_url}/api/rooms/{self.room_id}/participants")
            
            if response.status_code == 200:
                data = response.json()
                if 'participants' in data and isinstance(data['participants'], list):
                    participants = data['participants']
                    if len(participants) > 0:
                        # Store participant ID for approval test
                        self.participant_id = participants[0]['participant_id']
                        self.log_test("Participants List Endpoint", True, f"Found {len(participants)} participants")
                        return True
                    else:
                        self.log_test("Participants List Endpoint", True, "No participants found (expected)")
                        return True
                else:
                    self.log_test("Participants List Endpoint", False, f"Invalid response format: {data}")
                    return False
            else:
                self.log_test("Participants List Endpoint", False, f"Status code: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Participants List Endpoint", False, f"Error: {str(e)}")
            return False

    def test_participant_approval_endpoint(self):
        """Test 7: Test participant approval endpoint"""
        if not self.participant_id:
            self.log_test("Participant Approval Endpoint", False, "No participant ID available")
            return False
            
        try:
            response = requests.post(f"{self.base_url}/api/participants/{self.participant_id}/approve")
            
            if response.status_code == 200:
                data = response.json()
                if 'message' in data:
                    self.log_test("Participant Approval Endpoint", True, f"Response: {data['message']}")
                    return True
                else:
                    self.log_test("Participant Approval Endpoint", False, f"Unexpected response: {data}")
                    return False
            else:
                self.log_test("Participant Approval Endpoint", False, f"Status code: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Participant Approval Endpoint", False, f"Error: {str(e)}")
            return False

    def test_poll_creation_endpoint(self):
        """Test 8: Test poll creation endpoint"""
        if not self.room_id:
            self.log_test("Poll Creation Endpoint", False, "No room ID available")
            return False
            
        try:
            poll_data = {
                "room_id": self.room_id,
                "question": "What is your favorite programming language?",
                "options": ["Python", "JavaScript", "Java", "Go"]
            }
            response = requests.post(f"{self.base_url}/api/polls/create", json=poll_data)
            
            if response.status_code == 200:
                data = response.json()
                if 'poll_id' in data and 'question' in data and 'options' in data:
                    self.poll_id = data['poll_id']
                    self.log_test("Poll Creation Endpoint", True, f"Created poll: {data['question']}")
                    return True
                else:
                    self.log_test("Poll Creation Endpoint", False, f"Missing required fields: {data}")
                    return False
            else:
                self.log_test("Poll Creation Endpoint", False, f"Status code: {response.status_code}, Response: {response.text}")
                return False
        except Exception as e:
            self.log_test("Poll Creation Endpoint", False, f"Error: {str(e)}")
            return False

    def test_poll_start_endpoint(self):
        """Test 9: Test poll start endpoint"""
        if not self.poll_id:
            self.log_test("Poll Start Endpoint", False, "No poll ID available")
            return False
            
        try:
            response = requests.post(f"{self.base_url}/api/polls/{self.poll_id}/start")
            
            if response.status_code == 200:
                data = response.json()
                if 'message' in data:
                    self.log_test("Poll Start Endpoint", True, f"Response: {data['message']}")
                    return True
                else:
                    self.log_test("Poll Start Endpoint", False, f"Unexpected response: {data}")
                    return False
            else:
                self.log_test("Poll Start Endpoint", False, f"Status code: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Poll Start Endpoint", False, f"Error: {str(e)}")
            return False

    def test_voting_endpoint(self):
        """Test 10: Test voting endpoint"""
        if not self.poll_id or not self.participant_token:
            self.log_test("Voting Endpoint", False, "No poll ID or participant token available")
            return False
            
        try:
            vote_data = {
                "participant_token": self.participant_token,
                "selected_option": "Python"
            }
            response = requests.post(f"{self.base_url}/api/polls/{self.poll_id}/vote", json=vote_data)
            
            if response.status_code == 200:
                data = response.json()
                if 'message' in data:
                    self.log_test("Voting Endpoint", True, f"Response: {data['message']}")
                    return True
                else:
                    self.log_test("Voting Endpoint", False, f"Unexpected response: {data}")
                    return False
            else:
                self.log_test("Voting Endpoint", False, f"Status code: {response.status_code}, Response: {response.text}")
                return False
        except Exception as e:
            self.log_test("Voting Endpoint", False, f"Error: {str(e)}")
            return False

    def test_polls_list_endpoint(self):
        """Test 11: Test polls list endpoint"""
        if not self.room_id:
            self.log_test("Polls List Endpoint", False, "No room ID available")
            return False
            
        try:
            response = requests.get(f"{self.base_url}/api/rooms/{self.room_id}/polls")
            
            if response.status_code == 200:
                data = response.json()
                if 'polls' in data and isinstance(data['polls'], list):
                    polls = data['polls']
                    if len(polls) > 0:
                        poll = polls[0]
                        required_fields = ['poll_id', 'question', 'options', 'is_active', 'vote_counts', 'total_votes']
                        if all(field in poll for field in required_fields):
                            self.log_test("Polls List Endpoint", True, f"Found {len(polls)} polls with complete data")
                            return True
                        else:
                            self.log_test("Polls List Endpoint", False, f"Missing required fields in poll data")
                            return False
                    else:
                        self.log_test("Polls List Endpoint", True, "No polls found (expected)")
                        return True
                else:
                    self.log_test("Polls List Endpoint", False, f"Invalid response format: {data}")
                    return False
            else:
                self.log_test("Polls List Endpoint", False, f"Status code: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("Polls List Endpoint", False, f"Error: {str(e)}")
            return False

    def test_mongodb_connection(self):
        """Test 12: Verify MongoDB connection is working (indirect test)"""
        # We test MongoDB connection indirectly by checking if data persists
        if not self.room_id:
            self.log_test("MongoDB Connection", False, "No room ID to test persistence")
            return False
            
        try:
            # Get room status to verify data persistence
            response = requests.get(f"{self.base_url}/api/rooms/{self.room_id}/status")
            
            if response.status_code == 200:
                data = response.json()
                if data.get('room_id') == self.room_id and data.get('organizer_name') == self.organizer_name:
                    self.log_test("MongoDB Connection", True, "Data persistence verified - MongoDB working")
                    return True
                else:
                    self.log_test("MongoDB Connection", False, "Data mismatch - possible MongoDB issue")
                    return False
            else:
                self.log_test("MongoDB Connection", False, f"Cannot verify persistence - status: {response.status_code}")
                return False
        except Exception as e:
            self.log_test("MongoDB Connection", False, f"Error: {str(e)}")
            return False

    def cleanup_test_data(self):
        """Clean up test data"""
        if self.room_id:
            try:
                response = requests.delete(f"{self.base_url}/api/rooms/{self.room_id}/cleanup")
                if response.status_code == 200:
                    print(f"🧹 Cleaned up test room: {self.room_id}")
                else:
                    print(f"⚠️  Cleanup failed for room: {self.room_id}")
            except Exception as e:
                print(f"⚠️  Cleanup error: {str(e)}")

    def run_all_tests(self):
        """Run all basic backend functionality tests"""
        print("🚀 Starting Basic Backend Functionality Tests")
        print("=" * 60)
        
        # List of all tests to run
        tests = [
            self.test_backend_server_accessible,
            self.test_health_endpoint,
            self.test_room_creation_endpoint,
            self.test_room_join_endpoint,
            self.test_room_status_endpoint,
            self.test_participants_list_endpoint,
            self.test_participant_approval_endpoint,
            self.test_poll_creation_endpoint,
            self.test_poll_start_endpoint,
            self.test_voting_endpoint,
            self.test_polls_list_endpoint,
            self.test_mongodb_connection
        ]
        
        # Run all tests
        for test in tests:
            try:
                test()
            except Exception as e:
                self.log_test(test.__name__, False, f"Exception: {str(e)}")
        
        # Cleanup
        self.cleanup_test_data()
        
        # Print summary
        print("\n" + "=" * 60)
        print("📊 TEST SUMMARY")
        print("=" * 60)
        print(f"Total Tests: {self.tests_run}")
        print(f"Passed: {self.tests_passed}")
        print(f"Failed: {self.tests_run - self.tests_passed}")
        print(f"Success Rate: {(self.tests_passed / self.tests_run * 100):.1f}%")
        
        if self.tests_passed == self.tests_run:
            print("\n🎉 ALL BASIC BACKEND TESTS PASSED!")
            return True
        else:
            print(f"\n❌ {self.tests_run - self.tests_passed} TESTS FAILED!")
            return False

def main():
    """Main function"""
    tester = BasicBackendTester()
    success = tester.run_all_tests()
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())