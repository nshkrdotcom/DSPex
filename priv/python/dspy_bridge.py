#!/usr/bin/env python3
"""
DSPy Bridge for Elixir Integration

This module provides a communication bridge between Elixir and Python DSPy
processes using a JSON-based protocol with length-prefixed messages.

Features:
- Dynamic DSPy signature creation from Elixir definitions
- Program lifecycle management (create, execute, cleanup)
- Health monitoring and statistics
- Error handling and logging
- Memory management and cleanup

Protocol:
- 4-byte big-endian length header
- JSON message payload
- Request/response correlation with IDs

Usage:
    python3 dspy_bridge.py

The script reads from stdin and writes to stdout using the packet protocol.
"""

import sys
import json
import struct
import traceback
import time
import gc
import threading
import os
from typing import Dict, Any, Optional, List, Union

# Handle DSPy import with fallback
try:
    import dspy
    DSPY_AVAILABLE = True
except ImportError:
    DSPY_AVAILABLE = False
    print("Warning: DSPy not available. Some functionality will be limited.", file=sys.stderr)

# Handle Gemini import with fallback
try:
    import google.generativeai as genai
    GEMINI_AVAILABLE = True
except ImportError:
    GEMINI_AVAILABLE = False
    print("Warning: Google GenerativeAI not available. Gemini functionality will be limited.", file=sys.stderr)


class DSPyBridge:
    """
    Main bridge class handling DSPy program management and execution.
    
    This class maintains a registry of DSPy programs and handles command
    execution requests from the Elixir side.
    """
    
    def __init__(self):
        """Initialize the bridge with empty program registry."""
        self.programs: Dict[str, Any] = {}
        self.start_time = time.time()
        self.command_count = 0
        self.error_count = 0
        self.lock = threading.Lock()
        
        # Initialize DSPy if available
        if DSPY_AVAILABLE:
            self._initialize_dspy()
            
        # Initialize Gemini if available
        if GEMINI_AVAILABLE:
            self._initialize_gemini()
    
    def _initialize_dspy(self):
        """Initialize DSPy with default settings."""
        try:
            # Set up default DSPy configuration
            # This can be customized based on requirements
            pass
        except Exception as e:
            print(f"Warning: DSPy initialization failed: {e}", file=sys.stderr)
    
    def _initialize_gemini(self):
        """Initialize Gemini with API key from environment."""
        try:
            api_key = os.environ.get('GEMINI_API_KEY')
            if api_key:
                genai.configure(api_key=api_key)
                print("Gemini API configured successfully", file=sys.stderr)
            else:
                print("Warning: GEMINI_API_KEY not found in environment", file=sys.stderr)
        except Exception as e:
            print(f"Warning: Gemini initialization failed: {e}", file=sys.stderr)
    
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle incoming commands from Elixir.
        
        Args:
            command: The command name to execute
            args: Command arguments as a dictionary
            
        Returns:
            Dictionary containing the command result
            
        Raises:
            ValueError: If the command is unknown
            Exception: If command execution fails
        """
        with self.lock:
            self.command_count += 1
            
            handlers = {
                'ping': self.ping,
                'create_program': self.create_program,
                'create_gemini_program': self.create_gemini_program,
                'execute_program': self.execute_program,
                'execute_gemini_program': self.execute_gemini_program,
                'list_programs': self.list_programs,
                'delete_program': self.delete_program,
                'get_stats': self.get_stats,
                'cleanup': self.cleanup,
                'get_program_info': self.get_program_info
            }
            
            if command not in handlers:
                self.error_count += 1
                raise ValueError(f"Unknown command: {command}")
            
            try:
                result = handlers[command](args)
                return result
            except Exception as e:
                self.error_count += 1
                raise
    
    def ping(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Health check command.
        
        Args:
            args: Empty or containing optional parameters
            
        Returns:
            Status information including timestamp
        """
        return {
            "status": "ok",
            "timestamp": time.time(),
            "dspy_available": DSPY_AVAILABLE,
            "gemini_available": GEMINI_AVAILABLE,
            "uptime": time.time() - self.start_time
        }
    
    def create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new DSPy program from signature definition.
        
        Args:
            args: Dictionary containing:
                - id: Unique program identifier
                - signature: Signature definition with inputs/outputs
                - program_type: Type of program to create (default: 'predict')
                
        Returns:
            Dictionary with program creation status
        """
        if not DSPY_AVAILABLE:
            raise RuntimeError("DSPy not available - cannot create programs")
        
        program_id = args.get('id')
        signature_def = args.get('signature', {})
        program_type = args.get('program_type', 'predict')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id in self.programs:
            raise ValueError(f"Program with ID '{program_id}' already exists")
        
        try:
            # Create dynamic signature class
            signature_class = self._create_signature_class(signature_def)
            
            # Create program based on type
            program = self._create_program_instance(signature_class, program_type)
            
            # Store program
            self.programs[program_id] = {
                'program': program,
                'signature': signature_def,
                'created_at': time.time(),
                'execution_count': 0,
                'last_executed': None
            }
            
            return {
                "program_id": program_id,
                "status": "created",
                "signature": signature_def,
                "program_type": program_type
            }
            
        except Exception as e:
            raise RuntimeError(f"Failed to create program: {str(e)}")
    
    def _create_signature_class(self, signature_def: Dict[str, Any]) -> type:
        """
        Create a dynamic DSPy signature class from definition.
        
        Args:
            signature_def: Dictionary containing inputs and outputs
            
        Returns:
            Dynamic signature class
        """
        class DynamicSignature(dspy.Signature):
            pass
        
        inputs = signature_def.get('inputs', [])
        outputs = signature_def.get('outputs', [])
        
        # Add input fields
        for field in inputs:
            field_name = field.get('name')
            field_desc = field.get('description', '')
            
            if not field_name:
                raise ValueError("Input field must have a name")
            
            setattr(DynamicSignature, field_name, dspy.InputField(desc=field_desc))
        
        # Add output fields
        for field in outputs:
            field_name = field.get('name')
            field_desc = field.get('description', '')
            
            if not field_name:
                raise ValueError("Output field must have a name")
            
            setattr(DynamicSignature, field_name, dspy.OutputField(desc=field_desc))
        
        return DynamicSignature
    
    def _create_program_instance(self, signature_class: type, program_type: str) -> Any:
        """
        Create a DSPy program instance of the specified type.
        
        Args:
            signature_class: The signature class to use
            program_type: Type of program ('predict', 'chain_of_thought', etc.)
            
        Returns:
            DSPy program instance
        """
        if program_type == 'predict':
            return dspy.Predict(signature_class)
        elif program_type == 'chain_of_thought':
            return dspy.ChainOfThought(signature_class)
        elif program_type == 'react':
            return dspy.ReAct(signature_class)
        else:
            # Default to Predict for unknown types
            return dspy.Predict(signature_class)
    
    def execute_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute a DSPy program with given inputs.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program to execute
                - inputs: Input values for the program
                
        Returns:
            Dictionary containing program outputs
        """
        program_id = args.get('program_id')
        inputs = args.get('inputs', {})
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program_info = self.programs[program_id]
        program = program_info['program']
        
        try:
            # Execute the program
            result = program(**inputs)
            
            # Update execution statistics
            program_info['execution_count'] += 1
            program_info['last_executed'] = time.time()
            
            # Convert result to dictionary
            if hasattr(result, '__dict__'):
                output = {k: v for k, v in result.__dict__.items() 
                         if not k.startswith('_')}
            else:
                output = {"result": str(result)}
            
            return {
                "program_id": program_id,
                "outputs": output,
                "execution_time": time.time()
            }
            
        except Exception as e:
            raise RuntimeError(f"Program execution failed: {str(e)}")
    
    def list_programs(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        List all available programs.
        
        Args:
            args: Empty or containing optional filters
            
        Returns:
            Dictionary with program list and metadata
        """
        program_list = []
        
        for program_id, program_info in self.programs.items():
            program_list.append({
                "id": program_id,
                "created_at": program_info['created_at'],
                "execution_count": program_info['execution_count'],
                "last_executed": program_info['last_executed'],
                "signature": program_info['signature']
            })
        
        return {
            "programs": program_list,
            "total_count": len(program_list)
        }
    
    def delete_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Delete a program and free its resources.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program to delete
                
        Returns:
            Dictionary with deletion status
        """
        program_id = args.get('program_id')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        del self.programs[program_id]
        
        # Trigger garbage collection to free memory
        gc.collect()
        
        return {
            "program_id": program_id,
            "status": "deleted"
        }
    
    def get_program_info(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get detailed information about a specific program.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program
                
        Returns:
            Dictionary with program information
        """
        program_id = args.get('program_id')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program_info = self.programs[program_id]
        
        return {
            "program_id": program_id,
            "signature": program_info['signature'],
            "created_at": program_info['created_at'],
            "execution_count": program_info['execution_count'],
            "last_executed": program_info['last_executed']
        }
    
    def get_stats(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get bridge statistics and performance metrics.
        
        Args:
            args: Empty or containing optional parameters
            
        Returns:
            Dictionary with statistics
        """
        return {
            "programs_count": len(self.programs),
            "command_count": self.command_count,
            "error_count": self.error_count,
            "uptime": time.time() - self.start_time,
            "memory_usage": self._get_memory_usage(),
            "dspy_available": DSPY_AVAILABLE,
            "gemini_available": GEMINI_AVAILABLE
        }
    
    def cleanup(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Clean up all programs and free resources.
        
        Args:
            args: Empty or containing optional parameters
            
        Returns:
            Dictionary with cleanup status
        """
        program_count = len(self.programs)
        self.programs.clear()
        
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "cleaned",
            "programs_removed": program_count
        }
    
    def _get_memory_usage(self) -> Dict[str, Union[int, str]]:
        """
        Get current memory usage statistics.
        
        Returns:
            Dictionary with memory information
        """
        try:
            import psutil
            process = psutil.Process()
            memory_info = process.memory_info()
            
            return {
                "rss": memory_info.rss,
                "vms": memory_info.vms,
                "percent": process.memory_percent()
            }
        except ImportError:
            return {
                "rss": 0,
                "vms": 0,
                "percent": 0,
                "error": "psutil not available"
            }
    
    def create_gemini_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a Gemini-based program (custom implementation).
        
        Args:
            args: Dictionary containing:
                - id: Unique program identifier
                - signature: Signature definition with inputs/outputs
                - model: Gemini model name (optional, defaults to gemini-1.5-flash)
                
        Returns:
            Dictionary with program creation status
        """
        if not GEMINI_AVAILABLE:
            raise RuntimeError("Gemini not available - cannot create Gemini programs")
        
        program_id = args.get('id')
        signature_def = args.get('signature', {})
        model_name = args.get('model', 'gemini-1.5-flash')
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id in self.programs:
            raise ValueError(f"Program with ID '{program_id}' already exists")
        
        try:
            # Create Gemini model instance
            model = genai.GenerativeModel(model_name)
            
            # Store program with Gemini-specific metadata
            self.programs[program_id] = {
                'type': 'gemini',
                'model': model,
                'model_name': model_name,
                'signature': signature_def,
                'created_at': time.time(),
                'execution_count': 0,
                'last_executed': None
            }
            
            return {
                "program_id": program_id,
                "status": "created",
                "type": "gemini",
                "model_name": model_name,
                "signature": signature_def
            }
            
        except Exception as e:
            raise RuntimeError(f"Failed to create Gemini program: {str(e)}")
    
    def execute_gemini_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute a Gemini program with given inputs.
        
        Args:
            args: Dictionary containing:
                - program_id: ID of the program to execute
                - inputs: Input values for the program
                
        Returns:
            Dictionary containing program outputs
        """
        program_id = args.get('program_id')
        inputs = args.get('inputs', {})
        
        if not program_id:
            raise ValueError("Program ID is required")
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program_info = self.programs[program_id]
        
        if program_info.get('type') != 'gemini':
            raise ValueError(f"Program {program_id} is not a Gemini program")
        
        model = program_info['model']
        signature_def = program_info['signature']
        
        try:
            # Build prompt from signature and inputs
            prompt = self._build_gemini_prompt(signature_def, inputs)
            
            # Execute with Gemini
            response = model.generate_content(prompt)
            
            # Parse response according to signature
            outputs = self._parse_gemini_response(signature_def, response.text)
            
            # Update execution statistics
            program_info['execution_count'] += 1
            program_info['last_executed'] = time.time()
            
            return {
                "program_id": program_id,
                "outputs": outputs,
                "execution_time": time.time(),
                "raw_response": response.text
            }
            
        except Exception as e:
            raise RuntimeError(f"Gemini program execution failed: {str(e)}")
    
    def _build_gemini_prompt(self, signature_def: Dict[str, Any], inputs: Dict[str, Any]) -> str:
        """Build a prompt for Gemini based on signature and inputs."""
        
        # Get signature information
        input_fields = signature_def.get('inputs', [])
        output_fields = signature_def.get('outputs', [])
        
        # Build the prompt
        prompt_parts = []
        
        # Add instruction based on signature
        if len(output_fields) == 1:
            output_field = output_fields[0]
            instruction = f"Please provide {output_field.get('description', output_field.get('name', 'an answer'))}."
        else:
            output_names = [field.get('name', 'output') for field in output_fields]
            instruction = f"Please provide the following: {', '.join(output_names)}."
        
        prompt_parts.append(instruction)
        
        # Add input information
        for field in input_fields:
            field_name = field.get('name')
            field_value = inputs.get(field_name, '')
            field_desc = field.get('description', '')
            
            if field_desc:
                prompt_parts.append(f"{field_desc}: {field_value}")
            else:
                prompt_parts.append(f"{field_name}: {field_value}")
        
        # Add output format instruction
        output_format_parts = []
        for field in output_fields:
            field_name = field.get('name')
            field_desc = field.get('description', '')
            if field_desc:
                output_format_parts.append(f"{field_name}: [your {field_desc.lower()}]")
            else:
                output_format_parts.append(f"{field_name}: [your response]")
        
        if output_format_parts:
            prompt_parts.append(f"\nPlease respond in this format:\n{chr(10).join(output_format_parts)}")
        
        return "\n\n".join(prompt_parts)
    
    def _parse_gemini_response(self, signature_def: Dict[str, Any], response_text: str) -> Dict[str, str]:
        """Parse Gemini response according to signature definition."""
        
        output_fields = signature_def.get('outputs', [])
        outputs = {}
        
        # Simple parsing - look for "field_name:" patterns
        lines = response_text.strip().split('\n')
        
        for field in output_fields:
            field_name = field.get('name')
            
            # Look for the field in the response
            field_value = ""
            for line in lines:
                if line.lower().startswith(f"{field_name.lower()}:"):
                    field_value = line.split(':', 1)[1].strip()
                    break
            
            # If not found in structured format, use the whole response for single output
            if not field_value and len(output_fields) == 1:
                field_value = response_text.strip()
            
            outputs[field_name] = field_value
        
        return outputs


def read_message() -> Optional[Dict[str, Any]]:
    """
    Read a length-prefixed message from stdin.
    
    Returns:
        Parsed JSON message or None if EOF/error
    """
    try:
        # Read 4-byte length header
        length_bytes = sys.stdin.buffer.read(4)
        if len(length_bytes) < 4:
            return None
        
        length = struct.unpack('>I', length_bytes)[0]
        
        # Read message payload
        message_bytes = sys.stdin.buffer.read(length)
        if len(message_bytes) < length:
            return None
        
        # Parse JSON
        message_str = message_bytes.decode('utf-8')
        return json.loads(message_str)
        
    except (EOFError, json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"Error reading message: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Unexpected error reading message: {e}", file=sys.stderr)
        return None


def write_message(message: Dict[str, Any]) -> None:
    """
    Write a length-prefixed message to stdout.
    
    Args:
        message: Dictionary to send as JSON
    """
    try:
        # Encode message as JSON
        message_str = json.dumps(message, ensure_ascii=False)
        message_bytes = message_str.encode('utf-8')
        length = len(message_bytes)
        
        # Write length header (4 bytes, big-endian) + message
        sys.stdout.buffer.write(struct.pack('>I', length))
        sys.stdout.buffer.write(message_bytes)
        sys.stdout.buffer.flush()
        
    except Exception as e:
        print(f"Error writing message: {e}", file=sys.stderr)


def main():
    """
    Main event loop for the DSPy bridge.
    
    Reads messages from stdin, processes commands, and writes responses to stdout.
    """
    bridge = DSPyBridge()
    
    print("DSPy Bridge started", file=sys.stderr)
    print(f"DSPy available: {DSPY_AVAILABLE}", file=sys.stderr)
    
    try:
        while True:
            # Read incoming message
            message = read_message()
            if message is None:
                print("No more messages, exiting", file=sys.stderr)
                break
            
            # Extract message components
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            if request_id is None or command is None:
                print(f"Invalid message format: {message}", file=sys.stderr)
                continue
            
            try:
                # Execute command
                result = bridge.handle_command(command, args)
                
                # Send success response
                response = {
                    'id': request_id,
                    'success': True,
                    'result': result,
                    'timestamp': time.time()
                }
                write_message(response)
                
            except Exception as e:
                # Send error response
                error_response = {
                    'id': request_id,
                    'success': False,
                    'error': str(e),
                    'timestamp': time.time()
                }
                write_message(error_response)
                
                # Log error details
                print(f"Command error: {e}", file=sys.stderr)
                print(traceback.format_exc(), file=sys.stderr)
    
    except KeyboardInterrupt:
        print("Bridge interrupted by user", file=sys.stderr)
    except Exception as e:
        print(f"Unexpected bridge error: {e}", file=sys.stderr)
        print(traceback.format_exc(), file=sys.stderr)
    finally:
        print("DSPy Bridge shutting down", file=sys.stderr)


if __name__ == '__main__':
    main()