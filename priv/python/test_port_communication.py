#!/usr/bin/env python3
"""
Minimal test script to debug port communication
"""
import sys
import struct
import json

def log(msg):
    """Log to stderr for debugging"""
    print(f"[DEBUG] {msg}", file=sys.stderr)
    sys.stderr.flush()

def main():
    log("Test script started")
    log(f"Python version: {sys.version}")
    log(f"Arguments: {sys.argv}")
    
    # Read message with logging
    try:
        log("Waiting for 4-byte header...")
        length_bytes = sys.stdin.buffer.read(4)
        log(f"Read {len(length_bytes)} header bytes: {length_bytes.hex()}")
        
        if len(length_bytes) != 4:
            log("ERROR: Invalid header length")
            sys.exit(1)
            
        length = struct.unpack('>I', length_bytes)[0]
        log(f"Message length: {length}")
        
        log(f"Reading {length} bytes of payload...")
        payload = sys.stdin.buffer.read(length)
        log(f"Read {len(payload)} payload bytes")
        
        # Decode JSON
        message = json.loads(payload.decode('utf-8'))
        log(f"Decoded message: {message}")
        
        # Send response
        response = {
            "id": message.get("id", 0),
            "success": True,
            "result": {"status": "ok", "message": "Test successful"},
            "timestamp": "2025-01-14T00:00:00Z"
        }
        
        response_json = json.dumps(response)
        response_bytes = response_json.encode('utf-8')
        
        # Write length-prefixed response
        length_header = struct.pack('>I', len(response_bytes))
        log(f"Sending response: {len(response_bytes)} bytes")
        
        sys.stdout.buffer.write(length_header)
        sys.stdout.buffer.write(response_bytes)
        sys.stdout.buffer.flush()
        
        log("Response sent successfully")
        
    except Exception as e:
        log(f"ERROR: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()