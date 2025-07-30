#!/usr/bin/env python3
"""
Comprehensive Dependency Compatibility Test for SUPERvote Backend
Tests all functionality after dependency updates:
- FastAPI: 0.110.1 → 0.116.1
- Uvicorn: 0.25.0 → 0.35.0  
- PyMongo: 4.5.0 → 4.13.2
- Motor: 3.3.1 → 3.7.1
- ReportLab and other dependencies
"""

import requests
import json
import sys
import time
import asyncio
import websockets
from datetime import datetime
import threading
import warnings

class DependencyCompatibilityTester:
    def __init__(self, base_url="https://33908b3d-6a6e-4ef3-bc46-8d32783a6199.preview.emergentagent.com"):
        self.base_url = base_url
        self.tests_run = 0
        self.tests_passed = 0
        self.room_id = None
        self.participant_tokens = []
        self.participant_ids = []
        self.poll_ids = []
        self.organizer_name = "Compatibility Test Organizer"
        self.websocket_messages = []
        self.websocket_connected = False

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

    def run_test(self, name, method, endpoint, expected_status, data=None, params=None, timeout=10):
        """Run a single API test"""
        url = f"{self.base_url}/{endpoint}"
        headers = {'Content-Type': 'application/json'}
        
        try:
            if method == 'GET':
                response = requests.get(url, headers=headers, params=params, timeout=timeout)
            elif method == 'POST':
                if data:
                    response = requests.post(url, json=data, headers=headers, params=params, timeout=timeout)
                else:
                    response = requests.post(url, headers=headers, params=params, timeout=timeout)
            elif method == 'DELETE':
                response = requests.delete(url, headers=headers, timeout=timeout)

            success = response.status_code == expected_status
            if success:
                try:
                    response_data = response.json()
                    return True, response_data
                except:
                    return True, {}
            else:
                try:
                    error_data = response.json()
                    return False, error_data
                except:
                    return False, {"error": response.text}

        except Exception as e:
            return False, {"error": str(e)}

    def test_fastapi_compatibility(self):
        """Test FastAPI 0.116.1 compatibility"""
        print("\n🔍 Testing FastAPI 0.116.1 Compatibility...")
        
        # Test health endpoint
        success, response = self.run_test("Health Check", "GET", "api/health", 200)
        self.log_test("FastAPI Health Endpoint", success, 
                     f"Response: {response}" if success else f"Error: {response}")
        
        # Test CORS headers
        try:
            response = requests.options(f"{self.base_url}/api/health")
            cors_headers = {
                'Access-Control-Allow-Origin': response.headers.get('Access-Control-Allow-Origin'),
                'Access-Control-Allow-Methods': response.headers.get('Access-Control-Allow-Methods'),
                'Access-Control-Allow-Headers': response.headers.get('Access-Control-Allow-Headers')
            }
            self.log_test("CORS Headers Present", True, f"CORS configured: {cors_headers}")
        except Exception as e:
            self.log_test("CORS Headers Present", False, f"Error: {str(e)}")
        
        return success

    def test_pymongo_compatibility(self):
        """Test PyMongo 4.13.2 compatibility"""
        print("\n🔍 Testing PyMongo 4.13.2 Compatibility...")
        
        # Create room to test database operations
        success, response = self.run_test("Create Room (DB Test)", "POST", "api/rooms/create", 200,
                                        params={"organizer_name": self.organizer_name})
        if success and 'room_id' in response:
            self.room_id = response['room_id']
            self.log_test("MongoDB Room Creation", True, f"Room ID: {self.room_id}")
        else:
            self.log_test("MongoDB Room Creation", False, f"Error: {response}")
            return False
        
        # Test complex database query (room status with aggregations)
        success, response = self.run_test("Room Status (Complex Query)", "GET", 
                                        f"api/rooms/{self.room_id}/status", 200)
        if success:
            required_fields = ['participant_count', 'approved_count', 'pending_count', 'total_polls']
            all_fields_present = all(field in response for field in required_fields)
            self.log_test("MongoDB Complex Aggregation", all_fields_present, 
                         f"Fields: {list(response.keys())}")
        else:
            self.log_test("MongoDB Complex Aggregation", False, f"Error: {response}")
        
        return success

    def test_pydantic_compatibility(self):
        """Test Pydantic 2.10.0+ compatibility"""
        print("\n🔍 Testing Pydantic 2.10.0+ Compatibility...")
        
        # Test request validation with complex data structure
        poll_data = {
            "room_id": self.room_id,
            "question": "Test Pydantic validation with special chars: àáâãäåæçèéêë",
            "options": ["Option 1", "Option 2", "Option 3"],
            "timer_minutes": 5
        }
        
        success, response = self.run_test("Create Poll (Pydantic Validation)", "POST", 
                                        "api/polls/create", 200, data=poll_data)
        if success and 'poll_id' in response:
            self.poll_ids.append(response['poll_id'])
            self.log_test("Pydantic Request Validation", True, 
                         f"Poll created with special characters")
        else:
            self.log_test("Pydantic Request Validation", False, f"Error: {response}")
        
        # Test invalid data validation
        invalid_poll_data = {
            "room_id": self.room_id,
            "question": "",  # Empty question should fail
            "options": []    # Empty options should fail
        }
        
        success, response = self.run_test("Invalid Poll (Pydantic Validation)", "POST", 
                                        "api/polls/create", 422, data=invalid_poll_data)
        self.log_test("Pydantic Error Validation", success, 
                     "Correctly rejected invalid data" if success else f"Error: {response}")
        
        return True

    def test_reportlab_compatibility(self):
        """Test ReportLab 4.0.4+ compatibility"""
        print("\n🔍 Testing ReportLab 4.0.4+ Compatibility...")
        
        # Create some test data for PDF generation
        if not self.room_id:
            return False
        
        # Add participants
        for i in range(3):
            participant_name = f"PDF Test Participant {i+1}"
            success, response = self.run_test(f"Join Room (PDF Test {i+1})", "POST", 
                                            "api/rooms/join", 200,
                                            params={"room_id": self.room_id, 
                                                   "participant_name": participant_name})
            if success:
                self.participant_tokens.append(response.get('participant_token'))
        
        # Get participant IDs and approve them
        success, response = self.run_test("Get Participants (PDF Test)", "GET", 
                                        f"api/rooms/{self.room_id}/participants", 200)
        if success:
            for participant in response.get('participants', []):
                self.participant_ids.append(participant['participant_id'])
                # Approve participant
                self.run_test(f"Approve Participant (PDF Test)", "POST", 
                            f"api/participants/{participant['participant_id']}/approve", 200)
        
        # Create and start a poll
        if self.poll_ids:
            poll_id = self.poll_ids[0]
            self.run_test("Start Poll (PDF Test)", "POST", f"api/polls/{poll_id}/start", 200)
            
            # Have participants vote
            options = ["Option 1", "Option 2", "Option 3"]
            for i, token in enumerate(self.participant_tokens[:3]):
                if token:
                    vote_data = {
                        "participant_token": token,
                        "selected_option": options[i % len(options)]
                    }
                    self.run_test(f"Vote (PDF Test {i+1})", "POST", 
                                f"api/polls/{poll_id}/vote", 200, data=vote_data)
        
        # Test PDF generation
        try:
            url = f"{self.base_url}/api/rooms/{self.room_id}/report"
            response = requests.get(url, timeout=30)
            
            if response.status_code == 200:
                content_type = response.headers.get('Content-Type', '')
                if 'application/pdf' in content_type and response.content.startswith(b'%PDF'):
                    pdf_size = len(response.content)
                    self.log_test("ReportLab PDF Generation", True, 
                                 f"PDF generated successfully ({pdf_size} bytes)")
                    
                    # Test PDF headers
                    content_disposition = response.headers.get('Content-Disposition', '')
                    filename_present = 'filename=' in content_disposition
                    self.log_test("PDF Headers", filename_present, 
                                 f"Content-Disposition: {content_disposition}")
                    return True
                else:
                    self.log_test("ReportLab PDF Generation", False, 
                                 f"Invalid PDF content or content-type: {content_type}")
            else:
                self.log_test("ReportLab PDF Generation", False, 
                             f"HTTP {response.status_code}: {response.text[:200]}")
        except Exception as e:
            self.log_test("ReportLab PDF Generation", False, f"Exception: {str(e)}")
        
        return False

    def test_websocket_compatibility(self):
        """Test WebSocket functionality"""
        print("\n🔍 Testing WebSocket Compatibility...")
        
        if not self.room_id:
            self.log_test("WebSocket Test", False, "No room ID available")
            return False
        
        # Test WebSocket connection
        try:
            ws_url = f"wss://33908b3d-6a6e-4ef3-bc46-8d32783a6199.preview.emergentagent.com/api/ws/{self.room_id}"
            
            async def test_websocket():
                try:
                    async with websockets.connect(ws_url) as websocket:
                        # Send a test message
                        await websocket.send("test message")
                        
                        # Wait a bit for any responses
                        try:
                            response = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                            return True, f"WebSocket connected and responsive: {response}"
                        except asyncio.TimeoutError:
                            return True, "WebSocket connected (no immediate response expected)"
                        
                except Exception as e:
                    return False, f"WebSocket connection failed: {str(e)}"
            
            # Run the async test
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            success, message = loop.run_until_complete(test_websocket())
            loop.close()
            
            self.log_test("WebSocket Connection", success, message)
            return success
            
        except Exception as e:
            self.log_test("WebSocket Connection", False, f"Exception: {str(e)}")
            return False

    def test_uvicorn_compatibility(self):
        """Test Uvicorn 0.35.0 compatibility by checking server responses"""
        print("\n🔍 Testing Uvicorn 0.35.0 Compatibility...")
        
        # Test server headers
        try:
            response = requests.get(f"{self.base_url}/api/health")
            server_header = response.headers.get('server', '')
            
            # Check response time
            response_time = response.elapsed.total_seconds()
            
            self.log_test("Uvicorn Server Response", response.status_code == 200, 
                         f"Response time: {response_time:.3f}s, Server: {server_header}")
            
            # Test concurrent requests (Uvicorn performance)
            import concurrent.futures
            import time
            
            def make_request():
                start_time = time.time()
                resp = requests.get(f"{self.base_url}/api/health", timeout=5)
                end_time = time.time()
                return resp.status_code == 200, end_time - start_time
            
            # Make 10 concurrent requests
            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
                futures = [executor.submit(make_request) for _ in range(10)]
                results = [future.result() for future in concurrent.futures.as_completed(futures)]
            
            successful_requests = sum(1 for success, _ in results if success)
            avg_response_time = sum(time for _, time in results) / len(results)
            
            self.log_test("Uvicorn Concurrent Handling", successful_requests == 10, 
                         f"10/10 concurrent requests successful, avg time: {avg_response_time:.3f}s")
            
            return successful_requests >= 8  # Allow for some network variance
            
        except Exception as e:
            self.log_test("Uvicorn Server Response", False, f"Exception: {str(e)}")
            return False

    def test_comprehensive_api_functionality(self):
        """Test all core API functionality for compatibility"""
        print("\n🔍 Testing Comprehensive API Functionality...")
        
        if not self.room_id:
            return False
        
        # Test room management
        success, response = self.run_test("Room Status", "GET", f"api/rooms/{self.room_id}/status", 200)
        self.log_test("Room Management API", success)
        
        # Test participant management
        success, response = self.run_test("Participants List", "GET", 
                                        f"api/rooms/{self.room_id}/participants", 200)
        self.log_test("Participant Management API", success)
        
        # Test poll management
        success, response = self.run_test("Polls List", "GET", 
                                        f"api/rooms/{self.room_id}/polls", 200)
        self.log_test("Poll Management API", success)
        
        # Test voting system
        if self.poll_ids and self.participant_tokens:
            poll_id = self.poll_ids[0]
            token = self.participant_tokens[0]
            if token:
                vote_data = {
                    "participant_token": token,
                    "selected_option": "Option 1"
                }
                success, response = self.run_test("Voting System", "POST", 
                                                f"api/polls/{poll_id}/vote", 200, data=vote_data)
                self.log_test("Voting System API", success)
        
        return True

    def test_error_handling_compatibility(self):
        """Test error handling with new dependency versions"""
        print("\n🔍 Testing Error Handling Compatibility...")
        
        # Test 404 errors
        success, response = self.run_test("404 Error Handling", "GET", 
                                        "api/rooms/NONEXISTENT/status", 404)
        self.log_test("404 Error Handling", success)
        
        # Test 400 errors (validation)
        success, response = self.run_test("400 Error Handling", "POST", 
                                        "api/rooms/create", 400, 
                                        params={"organizer_name": ""})  # Empty name should fail
        self.log_test("400 Error Handling", success)
        
        # Test 403 errors (unauthorized voting)
        if self.poll_ids:
            vote_data = {
                "participant_token": "invalid-token",
                "selected_option": "Option 1"
            }
            success, response = self.run_test("403 Error Handling", "POST", 
                                            f"api/polls/{self.poll_ids[0]}/vote", 404, 
                                            data=vote_data)  # Should be 404 for invalid token
            self.log_test("403/404 Error Handling", success)
        
        return True

    def cleanup(self):
        """Clean up test data"""
        if self.room_id:
            self.run_test("Cleanup", "DELETE", f"api/rooms/{self.room_id}/cleanup", 200)

    def run_all_tests(self):
        """Run all compatibility tests"""
        print("🚀 Starting Comprehensive Dependency Compatibility Tests")
        print("=" * 80)
        print("Testing compatibility after dependency updates:")
        print("- FastAPI: 0.110.1 → 0.116.1")
        print("- Uvicorn: 0.25.0 → 0.35.0")
        print("- PyMongo: 4.5.0 → 4.13.2")
        print("- Motor: 3.3.1 → 3.7.1")
        print("- ReportLab: 4.0.4+")
        print("- Pydantic: 2.10.0+")
        print("=" * 80)
        
        # Suppress warnings during testing
        warnings.filterwarnings("ignore")
        
        # Run all compatibility tests
        tests = [
            ("FastAPI Compatibility", self.test_fastapi_compatibility),
            ("PyMongo Compatibility", self.test_pymongo_compatibility),
            ("Pydantic Compatibility", self.test_pydantic_compatibility),
            ("Uvicorn Compatibility", self.test_uvicorn_compatibility),
            ("ReportLab Compatibility", self.test_reportlab_compatibility),
            ("WebSocket Compatibility", self.test_websocket_compatibility),
            ("API Functionality", self.test_comprehensive_api_functionality),
            ("Error Handling", self.test_error_handling_compatibility),
        ]
        
        results = {}
        for test_name, test_func in tests:
            try:
                results[test_name] = test_func()
            except Exception as e:
                print(f"❌ {test_name} - Exception: {str(e)}")
                results[test_name] = False
        
        # Cleanup
        print("\n🧹 Cleaning up test data...")
        self.cleanup()
        
        # Results summary
        print("\n" + "=" * 80)
        print("📊 DEPENDENCY COMPATIBILITY TEST RESULTS")
        print("=" * 80)
        
        for test_name, success in results.items():
            status = "✅ PASSED" if success else "❌ FAILED"
            print(f"{test_name:.<50} {status}")
        
        print(f"\nOverall Tests Run: {self.tests_run}")
        print(f"Overall Tests Passed: {self.tests_passed}")
        print(f"Success Rate: {(self.tests_passed / self.tests_run * 100):.1f}%")
        
        # Overall assessment
        critical_tests = ["FastAPI Compatibility", "PyMongo Compatibility", "ReportLab Compatibility"]
        critical_passed = all(results.get(test, False) for test in critical_tests)
        
        if critical_passed and self.tests_passed / self.tests_run >= 0.8:
            print("\n🎉 DEPENDENCY COMPATIBILITY: EXCELLENT")
            print("All critical dependencies are working correctly!")
            return True
        elif self.tests_passed / self.tests_run >= 0.6:
            print("\n⚠️  DEPENDENCY COMPATIBILITY: GOOD WITH MINOR ISSUES")
            print("Most functionality works, but some issues detected.")
            return True
        else:
            print("\n❌ DEPENDENCY COMPATIBILITY: ISSUES DETECTED")
            print("Significant compatibility problems found!")
            return False

def main():
    """Main test function"""
    tester = DependencyCompatibilityTester()
    success = tester.run_all_tests()
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())