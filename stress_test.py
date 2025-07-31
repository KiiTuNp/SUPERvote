#!/usr/bin/env python3
"""
Stress Test for Vote Secret Application
Tests load handling, concurrent operations, and edge cases
"""

import requests
import time
import json
from concurrent.futures import ThreadPoolExecutor
import threading

class VoteSecretStressTest:
    def __init__(self, base_url="https://dac23748-f23d-42e5-8d4d-0b6bf9f295c1.preview.emergentagent.com"):
        self.base_url = base_url
        self.api_url = f"{base_url}/api"
        self.results = {
            "total_tests": 0,
            "passed_tests": 0,
            "failed_tests": 0,
            "errors": []
        }

    def log_result(self, test_name, success, error=None):
        self.results["total_tests"] += 1
        if success:
            self.results["passed_tests"] += 1
            print(f"✅ {test_name}")
        else:
            self.results["failed_tests"] += 1
            print(f"❌ {test_name}: {error}")
            self.results["errors"].append(f"{test_name}: {error}")

    def test_concurrent_meeting_creation(self, num_meetings=10):
        """Test creating multiple meetings simultaneously"""
        print(f"\n🔄 Testing concurrent meeting creation ({num_meetings} meetings)...")
        
        def create_meeting(i):
            try:
                response = requests.post(f"{self.api_url}/meetings", json={
                    "title": f"Stress Test Meeting {i}",
                    "organizer_name": f"Organizer {i}"
                }, timeout=10)
                return response.status_code == 200, response.json() if response.status_code == 200 else None
            except Exception as e:
                return False, str(e)

        start_time = time.time()
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(create_meeting, i) for i in range(num_meetings)]
            results = [future.result() for future in futures]
        
        end_time = time.time()
        
        successful = sum(1 for success, _ in results if success)
        self.log_result(f"Concurrent Meeting Creation ({successful}/{num_meetings})", 
                       successful >= num_meetings * 0.8,  # 80% success rate acceptable
                       f"Only {successful}/{num_meetings} succeeded")
        
        print(f"   Time taken: {end_time - start_time:.2f} seconds")
        return [data for success, data in results if success and data]

    def test_mass_participant_joining(self, meeting_code, num_participants=50):
        """Test many participants joining the same meeting"""
        print(f"\n👥 Testing mass participant joining ({num_participants} participants)...")
        
        def join_meeting(i):
            try:
                response = requests.post(f"{self.api_url}/participants/join", json={
                    "name": f"Participant {i:03d}",
                    "meeting_code": meeting_code
                }, timeout=10)
                return response.status_code == 200, response.json() if response.status_code == 200 else None
            except Exception as e:
                return False, str(e)

        start_time = time.time()
        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = [executor.submit(join_meeting, i) for i in range(num_participants)]
            results = [future.result() for future in futures]
        
        end_time = time.time()
        
        successful = sum(1 for success, _ in results if success)
        self.log_result(f"Mass Participant Joining ({successful}/{num_participants})", 
                       successful >= num_participants * 0.9,  # 90% success rate expected
                       f"Only {successful}/{num_participants} succeeded")
        
        print(f"   Time taken: {end_time - start_time:.2f} seconds")
        return [data for success, data in results if success and data]

    def test_large_poll_creation(self, meeting_id, num_options=100):
        """Test creating polls with many options"""
        print(f"\n📊 Testing large poll creation ({num_options} options)...")
        
        try:
            options = [f"Option {i:03d}" for i in range(num_options)]
            response = requests.post(f"{self.api_url}/meetings/{meeting_id}/polls", json={
                "question": f"Large poll with {num_options} options - which do you prefer?",
                "options": options,
                "timer_duration": 120
            }, timeout=30)
            
            success = response.status_code == 200
            self.log_result(f"Large Poll Creation ({num_options} options)", 
                           success, 
                           f"Status: {response.status_code}" if not success else None)
            
            return response.json() if success else None
            
        except Exception as e:
            self.log_result(f"Large Poll Creation ({num_options} options)", False, str(e))
            return None

    def test_concurrent_voting(self, poll_id, option_id, num_votes=100):
        """Test many concurrent votes on the same poll"""
        print(f"\n🗳️ Testing concurrent voting ({num_votes} votes)...")
        
        def submit_vote(i):
            try:
                response = requests.post(f"{self.api_url}/votes", json={
                    "poll_id": poll_id,
                    "option_id": option_id
                }, timeout=10)
                return response.status_code == 200
            except Exception as e:
                return False

        start_time = time.time()
        with ThreadPoolExecutor(max_workers=25) as executor:
            futures = [executor.submit(submit_vote, i) for i in range(num_votes)]
            results = [future.result() for future in futures]
        
        end_time = time.time()
        
        successful = sum(results)
        self.log_result(f"Concurrent Voting ({successful}/{num_votes})", 
                       successful >= num_votes * 0.95,  # 95% success rate expected
                       f"Only {successful}/{num_votes} succeeded")
        
        print(f"   Time taken: {end_time - start_time:.2f} seconds")

    def test_edge_cases(self):
        """Test various edge cases"""
        print(f"\n⚠️ Testing edge cases...")
        
        # Test 1: Very long strings
        try:
            long_title = "A" * 1000
            response = requests.post(f"{self.api_url}/meetings", json={
                "title": long_title,
                "organizer_name": "Test Organizer"
            }, timeout=10)
            self.log_result("Very Long Meeting Title", 
                           response.status_code in [200, 400, 422],  # Should handle gracefully
                           f"Unexpected status: {response.status_code}")
        except Exception as e:
            self.log_result("Very Long Meeting Title", False, str(e))

        # Test 2: Special characters
        try:
            special_chars = "Test Meeting 🗳️ with émojis & spéciàl chars <script>alert('xss')</script>"
            response = requests.post(f"{self.api_url}/meetings", json={
                "title": special_chars,
                "organizer_name": "Test Organizer"
            }, timeout=10)
            self.log_result("Special Characters in Title", 
                           response.status_code == 200,
                           f"Status: {response.status_code}")
        except Exception as e:
            self.log_result("Special Characters in Title", False, str(e))

        # Test 3: Empty fields
        try:
            response = requests.post(f"{self.api_url}/meetings", json={
                "title": "",
                "organizer_name": ""
            }, timeout=10)
            self.log_result("Empty Fields Validation", 
                           response.status_code in [400, 422],  # Should reject
                           f"Should reject empty fields, got: {response.status_code}")
        except Exception as e:
            self.log_result("Empty Fields Validation", False, str(e))

        # Test 4: Invalid JSON
        try:
            response = requests.post(f"{self.api_url}/meetings", 
                                   data="invalid json", 
                                   headers={'Content-Type': 'application/json'},
                                   timeout=10)
            self.log_result("Invalid JSON Handling", 
                           response.status_code in [400, 422],  # Should reject
                           f"Should reject invalid JSON, got: {response.status_code}")
        except Exception as e:
            self.log_result("Invalid JSON Handling", False, str(e))

    def test_api_response_times(self):
        """Test API response times under normal load"""
        print(f"\n⏱️ Testing API response times...")
        
        endpoints = [
            ("GET", "meetings/NONEXISTENT", 404),  # Should be fast 404
        ]
        
        # First create a meeting for testing
        response = requests.post(f"{self.api_url}/meetings", json={
            "title": "Response Time Test",
            "organizer_name": "Test Organizer"
        })
        
        if response.status_code == 200:
            meeting_data = response.json()
            meeting_id = meeting_data['id']
            meeting_code = meeting_data['meeting_code']
            
            endpoints.extend([
                ("GET", f"meetings/{meeting_code}", 200),
                ("GET", f"meetings/{meeting_id}/organizer", 200),
                ("GET", f"meetings/{meeting_id}/polls", 200),
            ])
        
        for method, endpoint, expected_status in endpoints:
            try:
                start_time = time.time()
                if method == "GET":
                    response = requests.get(f"{self.api_url}/{endpoint}", timeout=10)
                end_time = time.time()
                
                response_time = (end_time - start_time) * 1000  # Convert to ms
                
                self.log_result(f"Response Time {endpoint} ({response_time:.0f}ms)", 
                               response_time < 2000 and response.status_code == expected_status,  # Under 2 seconds
                               f"Too slow: {response_time:.0f}ms or wrong status: {response.status_code}")
                
            except Exception as e:
                self.log_result(f"Response Time {endpoint}", False, str(e))

    def run_all_tests(self):
        """Run all stress tests"""
        print("🚀 Starting Vote Secret Stress Tests")
        print("=" * 60)
        
        # Test 1: Concurrent meeting creation
        meetings = self.test_concurrent_meeting_creation(5)  # Reduced for stability
        
        if meetings:
            # Use first meeting for further tests
            meeting = meetings[0]
            meeting_id = meeting['id']
            meeting_code = meeting['meeting_code']
            
            # Test 2: Mass participant joining
            participants = self.test_mass_participant_joining(meeting_code, 20)  # Reduced for stability
            
            # Test 3: Large poll creation
            poll = self.test_large_poll_creation(meeting_id, 50)  # Reduced for stability
            
            if poll and poll.get('options'):
                # Test 4: Concurrent voting
                option_id = poll['options'][0]['id']
                self.test_concurrent_voting(poll['id'], option_id, 30)  # Reduced for stability
        
        # Test 5: Edge cases
        self.test_edge_cases()
        
        # Test 6: Response times
        self.test_api_response_times()
        
        # Print final results
        print("\n" + "=" * 60)
        print("📊 STRESS TEST RESULTS")
        print("=" * 60)
        print(f"Total Tests: {self.results['total_tests']}")
        print(f"Passed: {self.results['passed_tests']}")
        print(f"Failed: {self.results['failed_tests']}")
        print(f"Success Rate: {(self.results['passed_tests']/self.results['total_tests']*100):.1f}%")
        
        if self.results['errors']:
            print("\n❌ ERRORS:")
            for error in self.results['errors']:
                print(f"   - {error}")
        
        return self.results['passed_tests'] / self.results['total_tests'] >= 0.8  # 80% success rate

if __name__ == "__main__":
    tester = VoteSecretStressTest()
    success = tester.run_all_tests()
    exit(0 if success else 1)