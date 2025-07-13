#!/usr/bin/env python3
"""
Test the enhanced DSPy bridge with Gemini support
"""

import json
import struct
import subprocess
import time
import os
import sys

def send_message(process, message):
    """Send a length-prefixed JSON message to the bridge."""
    json_str = json.dumps(message)
    json_bytes = json_str.encode('utf-8')
    length = len(json_bytes)
    
    # Send length header (4 bytes, big-endian) + message
    process.stdin.write(struct.pack('>I', length))
    process.stdin.write(json_bytes)
    process.stdin.flush()

def read_message(process):
    """Read a length-prefixed JSON message from the bridge."""
    try:
        # Read 4-byte length header
        length_bytes = process.stdout.read(4)
        if len(length_bytes) < 4:
            return None
        
        length = struct.unpack('>I', length_bytes)[0]
        
        # Read message payload
        message_bytes = process.stdout.read(length)
        if len(message_bytes) < length:
            return None
        
        # Parse JSON
        message_str = message_bytes.decode('utf-8')
        return json.loads(message_str)
        
    except Exception as e:
        print(f"Error reading message: {e}")
        return None

def test_bridge_with_gemini():
    """Test the bridge with Gemini functionality."""
    
    # Check environment
    if not os.environ.get('GEMINI_API_KEY'):
        print("❌ GEMINI_API_KEY not set")
        return False
    
    print("🚀 Starting bridge with Gemini support...")
    
    try:
        # Start the bridge process
        process = subprocess.Popen(
            ['python3', 'priv/python/dspy_bridge.py'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Give it a moment to start
        time.sleep(1)
        
        # Test 1: Ping to check status
        print("📡 Testing ping...")
        ping_message = {
            "id": 1,
            "command": "ping",
            "args": {},
            "timestamp": time.time()
        }
        
        send_message(process, ping_message)
        response = read_message(process)
        
        if response and response.get('success'):
            result = response['result']
            print(f"✅ Ping successful: status={result['status']}")
            print(f"   DSPy available: {result.get('dspy_available', False)}")
            print(f"   Gemini available: {result.get('gemini_available', False)}")
            
            if not result.get('gemini_available'):
                print("❌ Gemini not available in bridge")
                return False
        else:
            print(f"❌ Ping failed: {response}")
            return False
        
        # Test 2: Create a Gemini program
        print("🛠️ Creating Gemini program...")
        create_message = {
            "id": 2,
            "command": "create_gemini_program",
            "args": {
                "id": "test_qa",
                "signature": {
                    "inputs": [{"name": "question", "description": "A question to answer"}],
                    "outputs": [{"name": "answer", "description": "A concise answer"}]
                },
                "model": "gemini-1.5-flash"
            },
            "timestamp": time.time()
        }
        
        send_message(process, create_message)
        response = read_message(process)
        
        if response and response.get('success'):
            result = response['result']
            print(f"✅ Program created: {result['program_id']} ({result['type']})")
        else:
            print(f"❌ Program creation failed: {response}")
            return False
        
        # Test 3: Execute the Gemini program
        print("🤖 Executing Gemini program...")
        execute_message = {
            "id": 3,
            "command": "execute_gemini_program",
            "args": {
                "program_id": "test_qa",
                "inputs": {
                    "question": "What is the capital of France?"
                }
            },
            "timestamp": time.time()
        }
        
        send_message(process, execute_message)
        response = read_message(process)
        
        if response and response.get('success'):
            result = response['result']
            outputs = result.get('outputs', {})
            answer = outputs.get('answer', 'No answer')
            print(f"✅ Execution successful!")
            print(f"   Question: What is the capital of France?")
            print(f"   Answer: {answer}")
            print(f"   Raw response: {result.get('raw_response', '')[:100]}...")
        else:
            print(f"❌ Execution failed: {response}")
            return False
        
        # Test 4: List programs
        print("📋 Listing programs...")
        list_message = {
            "id": 4,
            "command": "list_programs",
            "args": {},
            "timestamp": time.time()
        }
        
        send_message(process, list_message)
        response = read_message(process)
        
        if response and response.get('success'):
            result = response['result']
            programs = result.get('programs', [])
            print(f"✅ Found {len(programs)} programs")
            for prog in programs:
                print(f"   - {prog['id']} (executions: {prog['execution_count']})")
        else:
            print(f"❌ List failed: {response}")
        
        # Cleanup
        print("🧹 Cleaning up...")
        cleanup_message = {
            "id": 5,
            "command": "cleanup",
            "args": {},
            "timestamp": time.time()
        }
        
        send_message(process, cleanup_message)
        response = read_message(process)
        
        if response and response.get('success'):
            result = response['result']
            print(f"✅ Cleanup successful: removed {result['programs_removed']} programs")
        
        # Terminate the process
        process.terminate()
        process.wait()
        
        print("\n🎉 All tests passed! Gemini bridge is working!")
        return True
        
    except Exception as e:
        print(f"❌ Test failed with exception: {e}")
        if 'process' in locals():
            process.terminate()
        return False

if __name__ == "__main__":
    success = test_bridge_with_gemini()
    sys.exit(0 if success else 1)