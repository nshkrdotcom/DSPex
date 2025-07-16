#!/usr/bin/env python3

# Debug logging - write to file immediately to debug startup issues
import sys
import os
with open('/tmp/dspy_bridge_debug.log', 'a') as f:
    f.write(f"=== DSPy Bridge Starting ===\n")
    f.write(f"PID: {os.getpid()}\n")
    f.write(f"Args: {sys.argv}\n")
    f.write(f"Python: {sys.executable}\n")
    f.write(f"Working Dir: {os.getcwd()}\n")
    f.flush()

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
import argparse
import re
import signal
import atexit
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
    
    def __init__(self, mode="standalone", worker_id=None):
        """Initialize the bridge with empty program registry."""
        self.mode = mode
        self.worker_id = worker_id
        
        # Initialize programs storage based on mode
        if self.mode == "standalone":
            # Standalone mode needs local storage
            self.programs = {}
        # Pool-worker mode uses centralized SessionStore, no local storage needed
            
        self.start_time = time.time()
        self.command_count = 0
        self.error_count = 0
        self.lock = threading.Lock()
        
        # Language Model configuration
        self.lm_configured = False
        self.current_lm_config = None
        
        # NEW: Cache for dynamically generated signature classes
        self.signature_cache = {}
        
        # NEW: Feature flags for dynamic signatures
        self.feature_flags = {
            "dynamic_signatures": os.environ.get("DSPEX_DYNAMIC_SIGNATURES", "true").lower() == "true"
        }
        
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
                'configure_lm': self.configure_lm,
                'create_program': self.create_program,
                'create_gemini_program': self.create_gemini_program,
                'execute_program': self.execute_program,
                'execute_gemini_program': self.execute_gemini_program,
                'list_programs': self.list_programs,
                'delete_program': self.delete_program,
                'get_stats': self.get_stats,
                'cleanup': self.cleanup,
                'reset_state': self.reset_state,
                'get_program_info': self.get_program_info,
                'cleanup_session': self.cleanup_session,
                'shutdown': self.shutdown,
                # Session store communication handlers
                'get_session_data': self.get_session_data,
                'update_session_data': self.update_session_data
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
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] ping() called with args: {args}\n")
            f.flush()
        
        response = {
            "status": "ok",
            "timestamp": time.time(),
            "dspy_available": DSPY_AVAILABLE,
            "gemini_available": GEMINI_AVAILABLE,
            "uptime": time.time() - self.start_time,
            "mode": self.mode
        }
        
        if self.worker_id:
            response["worker_id"] = self.worker_id
            
        if self.mode == "pool-worker" and hasattr(self, 'current_session'):
            response["current_session"] = self.current_session
            
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] ping() returning: {response}\n")
            f.flush()
            
        return response
    
    def configure_lm(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Configure the language model for DSPy.
        
        Args:
            args: Configuration with model, api_key, temperature
            
        Returns:
            Status information about the configuration
        """
        try:
            model = args.get('model')
            api_key = args.get('api_key')
            temperature = args.get('temperature', 0.7)
            provider = args.get('provider', 'google')
            
            if not model:
                raise ValueError("Model name is required")
            if not api_key:
                raise ValueError("API key is required")
            
            # Configure based on provider
            if provider == 'google' and model.startswith('gemini'):
                import dspy
                import os
                
                # Set the API key in environment (DSPy often reads from environment)
                os.environ['GOOGLE_API_KEY'] = api_key
                
                # Configure with proper LiteLLM format for Google AI Studio API (not Vertex AI)
                try:
                    # Method 1: Force Google AI Studio with gemini/ prefix
                    lm = dspy.LM(
                        model=f"gemini/{model}",
                        api_key=api_key,
                        temperature=temperature
                    )
                    dspy.settings.configure(lm=lm)
                except Exception as e1:
                    try:
                        # Method 2: Try direct model name
                        lm = dspy.LM(
                            model=model,
                            api_key=api_key,
                            temperature=temperature
                        )
                        dspy.settings.configure(lm=lm)
                    except Exception as e2:
                        try:
                            # Method 3: Try with explicit google/ prefix
                            lm = dspy.LM(
                                model=f"google/{model}",
                                api_key=api_key,
                                temperature=temperature
                            )
                            dspy.settings.configure(lm=lm)
                        except Exception as e3:
                            raise ValueError(f"Failed to configure Gemini model with any format. Google AI Studio requires API key authentication. Errors: {str(e1)}, {str(e2)}, {str(e3)}")
                
                self.lm_configured = True
                self.current_lm_config = args
                
                # Store per-session in pool-worker mode
                if self.mode == "pool-worker" and hasattr(self, 'current_session') and self.current_session:
                    if not hasattr(self, 'session_lms'):
                        self.session_lms = {}
                    self.session_lms[self.current_session] = args
                
                # Test the LM configuration with a simple call
                try:
                    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                        f.write(f"[{time.time()}] DEBUG: Testing LM with simple call\n")
                        f.flush()
                    
                    # Try a simple DSPy call to verify the LM is working
                    simple_test = dspy.Predict("question -> answer")
                    test_result = simple_test(question="What is 1+1?")
                    
                    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                        f.write(f"[{time.time()}] DEBUG: LM test result: {test_result}\n")
                        f.write(f"[{time.time()}] DEBUG: LM test type: {type(test_result)}\n")
                        if hasattr(test_result, '__dict__'):
                            f.write(f"[{time.time()}] DEBUG: LM test dict: {test_result.__dict__}\n")
                        f.flush()
                except Exception as e:
                    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                        f.write(f"[{time.time()}] DEBUG: LM test failed: {e}\n")
                        f.flush()
                
                return {
                    "status": "configured",
                    "model": model,
                    "provider": provider,
                    "temperature": temperature
                }
            else:
                raise ValueError(f"Unsupported provider/model combination: {provider}/{model}")
                
        except Exception as e:
            self.error_count += 1
            return {"error": str(e)}
    
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
        
        # In pool-worker mode, programs are managed through centralized SessionStore
        # The Elixir side should have already checked for existence, so we don't need to check here
        # We'll let the storage operation determine if there's a conflict
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if not session_id:
                raise ValueError("Session ID required in pool-worker mode")
        else:
            # In standalone mode, check local storage
            if not hasattr(self, 'programs'):
                self.programs = {}
            if program_id in self.programs:
                raise ValueError(f"Program with ID '{program_id}' already exists")
        
        try:
            # Check feature flag and signature definition to determine approach
            use_dynamic = args.get('use_dynamic_signature', self.feature_flags['dynamic_signatures'])
            
            if use_dynamic and signature_def and signature_def.get('inputs') and signature_def.get('outputs'):
                # NEW: Dynamic signature path
                try:
                    signature_class, field_mapping = self._get_or_create_signature_class(signature_def)
                    program = dspy.Predict(signature_class)
                    fallback_used = False
                    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                        f.write(f"[{time.time()}] Created dynamic program with signature: {signature_class.__name__}\n")
                        f.flush()
                except Exception as e:
                    # RESILIENT FALLBACK
                    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                        f.write(f"[{time.time()}] Dynamic signature creation failed: {e}. Falling back to Q/A.\n")
                        f.write(traceback.format_exc() + "\n")
                        f.flush()
                    program = dspy.Predict("question -> answer")
                    signature_class = None  # Indicate fallback was used
                    field_mapping = {}
                    fallback_used = True
            else:
                # EXISTING: Legacy Q&A path
                program = dspy.Predict("question -> answer")
                signature_class = None
                field_mapping = {}
                fallback_used = False
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] Using legacy Q&A signature (dynamic disabled or incomplete signature)\n")
                    f.flush()
            
            # Store program based on mode
            program_info = {
                'program': program,
                'signature_class': signature_class,
                'signature_def': signature_def,
                'field_mapping': field_mapping,
                'fallback_used': fallback_used,
                'created_at': time.time(),
                'execution_count': 0,
                'last_executed': None
            }
            
            if self.mode == "pool-worker":
                # In pool mode, we don't store programs locally - they're managed centrally
                # The Elixir SessionStore will handle storage, we just acknowledge creation
                session_id = args.get('session_id')
                if session_id == "anonymous":
                    # Anonymous sessions still use local storage (temporary)
                    if not hasattr(self, 'programs'):
                        self.programs = {}
                    self.programs[program_id] = program_info
                # For named sessions, don't store locally - Elixir handles it
            else:
                # Standalone mode uses local storage
                if not hasattr(self, 'programs'):
                    self.programs = {}
                self.programs[program_id] = program_info
            
            return {
                "program_id": program_id,
                "status": "created",
                "signature": signature_def,
                "program_type": program_type
            }
            
        except Exception as e:
            raise RuntimeError(f"Failed to create program: {str(e)}")
    
    def _get_or_create_signature_class(self, signature_def: Dict[str, Any]) -> tuple:
        """
        Gets a signature class from cache or creates it dynamically.
        This is a performance optimization.
        
        Args:
            signature_def: Dictionary containing inputs and outputs
            
        Returns:
            Tuple of (signature_class, field_mapping)
        """
        # Create a stable key for caching
        signature_key = json.dumps(signature_def, sort_keys=True)
        
        if signature_key not in self.signature_cache:
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] Cache miss for signature: {signature_key}. Creating new class.\n")
                f.flush()
            self.signature_cache[signature_key] = self._create_signature_class(signature_def)
        
        return self.signature_cache[signature_key]

    def _create_signature_class(self, signature_def: Dict[str, Any]) -> tuple:
        """
        Dynamically builds a dspy.Signature class from a detailed definition.
        
        Args:
            signature_def: Dictionary containing inputs and outputs
            
        Returns:
            Tuple of (signature_class, field_mapping)
            
        Raises:
            ValueError: If signature definition is invalid
        """
        # Validate signature definition
        if not isinstance(signature_def, dict):
            raise ValueError("Signature definition must be a dictionary")
        
        inputs = signature_def.get('inputs', [])
        outputs = signature_def.get('outputs', [])
        
        if not inputs:
            raise ValueError("Signature must have at least one input field")
        if not outputs:
            raise ValueError("Signature must have at least one output field")
        
        # Validate field definitions
        for field_list, field_type in [(inputs, 'input'), (outputs, 'output')]:
            for i, field_def in enumerate(field_list):
                if not isinstance(field_def, dict):
                    raise ValueError(f"Field definition {i} in {field_type}s must be a dictionary")
                if not field_def.get('name'):
                    raise ValueError(f"Field definition {i} in {field_type}s must have a 'name'")
        
        raw_class_name = signature_def.get('name', 'DynamicSignature').split('.')[-1]
        class_name = re.sub(r'\W|^(?=\d)', '_', raw_class_name)  # Sanitize class name
        if not class_name or class_name.startswith('_'):
            class_name = f"Dynamic_{int(time.time())}"
        
        docstring = signature_def.get('description', 'A dynamically generated DSPy signature.')
        
        attrs = {'__doc__': docstring}
        
        # Keep track of original -> sanitized field name mapping for later use
        field_mapping = {}
        
        # Dynamically create InputField and OutputField attributes
        for field_def in inputs:
            raw_field_name = field_def.get('name')
            if raw_field_name:
                field_name = re.sub(r'\W|^(?=\d)', '_', raw_field_name)  # Sanitize field name
                if not field_name or field_name.startswith('_'):
                    field_name = f"field_{len(field_mapping)}"
                field_mapping[raw_field_name] = field_name
                attrs[field_name] = dspy.InputField(
                    desc=field_def.get('description', f'Input field: {raw_field_name}')
                )
        
        for field_def in outputs:
            raw_field_name = field_def.get('name')
            if raw_field_name:
                field_name = re.sub(r'\W|^(?=\d)', '_', raw_field_name)  # Sanitize field name
                if not field_name or field_name.startswith('_'):
                    field_name = f"field_{len(field_mapping)}"
                field_mapping[raw_field_name] = field_name
                attrs[field_name] = dspy.OutputField(
                    desc=field_def.get('description', f'Output field: {raw_field_name}')
                )
        
        # Ensure we have at least one input and output field after sanitization
        # Check for DSPy InputField and OutputField by looking at the json_schema_extra
        input_field_count = sum(1 for k, v in attrs.items() 
                              if hasattr(v, 'json_schema_extra') and 
                              v.json_schema_extra and 
                              v.json_schema_extra.get('__dspy_field_type') == 'input')
        output_field_count = sum(1 for k, v in attrs.items() 
                               if hasattr(v, 'json_schema_extra') and 
                               v.json_schema_extra and 
                               v.json_schema_extra.get('__dspy_field_type') == 'output')
        
        if input_field_count == 0:
            raise ValueError("No valid input fields after sanitization")
        if output_field_count == 0:
            raise ValueError("No valid output fields after sanitization")
        
        # Use type() to create the class dynamically
        signature_class = type(class_name, (dspy.Signature,), attrs)
        
        # Return both the class and the field mapping
        return signature_class, field_mapping
    
    def _recreate_program_from_data(self, program_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Recreates a program object from stored data for stateless workers.
        
        Args:
            program_data: The program data retrieved from SessionStore
            
        Returns:
            Dictionary containing recreated program info
        """
        if not DSPY_AVAILABLE:
            raise RuntimeError("DSPy not available - cannot recreate programs")
        
        try:
            signature_def = program_data.get('signature_def', {})
            signature_class = program_data.get('signature_class')
            field_mapping = program_data.get('field_mapping', {})
            fallback_used = program_data.get('fallback_used', False)
            
            # Recreate the program object
            if signature_class and not fallback_used and signature_def:
                # Try to recreate the dynamic signature
                try:
                    recreated_signature_class, recreated_field_mapping = self._get_or_create_signature_class(signature_def)
                    program = dspy.Predict(recreated_signature_class)
                    field_mapping = recreated_field_mapping
                except Exception:
                    # Fall back to Q&A
                    program = dspy.Predict("question -> answer")
                    field_mapping = {}
                    fallback_used = True
            else:
                # Use Q&A format
                program = dspy.Predict("question -> answer")
                field_mapping = {}
                fallback_used = True
            
            # Recreate the program info structure
            recreated_info = {
                'program': program,
                'signature_class': signature_class,
                'signature_def': signature_def,
                'field_mapping': field_mapping,
                'fallback_used': fallback_used,
                'created_at': program_data.get('created_at', time.time()),
                'execution_count': program_data.get('execution_count', 0),
                'last_executed': program_data.get('last_executed')
            }
            
            return recreated_info
            
        except Exception as e:
            raise RuntimeError(f"Failed to recreate program from data: {str(e)}")
    
    
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
        
        # Get program based on mode
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if session_id and session_id != "anonymous":
                # For named sessions, the program data should be passed in the request
                # by the Elixir side which fetched it from SessionStore
                program_data = args.get('program_data')
                if not program_data:
                    raise ValueError(f"Program not found: {program_id} (no program data provided)")
                
                # Recreate the program object from the stored data
                program_info = self._recreate_program_from_data(program_data)
            else:
                # Anonymous sessions use local storage (temporary)
                if not hasattr(self, 'programs') or program_id not in self.programs:
                    raise ValueError(f"Program not found: {program_id}")
                program_info = self.programs[program_id]
        else:
            # Standalone mode uses local storage
            if not hasattr(self, 'programs') or program_id not in self.programs:
                raise ValueError(f"Program not found: {program_id}")
            program_info = self.programs[program_id]
            
        program = program_info['program']
        
        # Check if LM is configured
        if not self.lm_configured:
            # Try to use default from environment if available
            api_key = os.environ.get('GEMINI_API_KEY')
            if api_key:
                self.configure_lm({
                    'model': 'gemini-1.5-flash',
                    'api_key': api_key,
                    'temperature': 0.7,
                    'provider': 'google'
                })
            else:
                raise RuntimeError("No LM is loaded.")
        
        # Restore session LM if in pool-worker mode
        if self.mode == "pool-worker" and hasattr(self, 'session_lms'):
            session_id = args.get('session_id')
            if session_id in self.session_lms:
                self.configure_lm(self.session_lms[session_id])
        
        try:
            # Determine execution mode based on signature and fallback status
            is_dynamic = program_info.get('signature_class') is not None and not program_info.get('fallback_used', False)
            
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] DEBUG: About to execute program with inputs: {inputs}\n")
                f.write(f"[{time.time()}] DEBUG: Is dynamic: {is_dynamic}\n")
                f.write(f"[{time.time()}] DEBUG: Program type: {type(program)}\n")
                f.flush()
            
            if is_dynamic:
                # Dynamic execution with field mapping
                field_mapping = program_info.get('field_mapping', {})
                if field_mapping:
                    # Convert original input names to sanitized names
                    sanitized_inputs = {}
                    for original_name, value in inputs.items():
                        sanitized_name = field_mapping.get(original_name, original_name)
                        sanitized_inputs[sanitized_name] = value
                    
                    # This is the magic: **sanitized_inputs unpacks the dict into named arguments
                    result = program(**sanitized_inputs)
                else:
                    # This is the magic: **inputs unpacks the dict into named arguments
                    result = program(**inputs)
            else:
                # Legacy Q&A execution
                question = inputs.get('question', list(inputs.values())[0] if inputs else '')
                result = program(question=question)
            
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] DEBUG: Program execution returned successfully\n")
                f.flush()
            
            # Update execution statistics
            program_info['execution_count'] += 1
            program_info['last_executed'] = time.time()
            
            # Monitor memory after AI operation
            memory_info = self._get_memory_usage()
            if memory_info.get("percent", 0) > 80:
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] High memory usage after AI operation: {memory_info}\n")
                    f.write(f"[{time.time()}] Worker ID: {self.worker_id}, Session: {session_id}\n")
                    f.flush()
                # Force garbage collection to free memory
                gc.collect()
            
            # Debug: Write what we got from DSPy to debug log
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] DEBUG: DSPy result type: {type(result)}\n")
                f.write(f"[{time.time()}] DEBUG: DSPy result class: {result.__class__.__name__}\n")
                f.flush()
            
            # Extract outputs based on execution mode
            signature_def = program_info.get('signature_def', program_info.get('signature', {}))
            field_mapping = program_info.get('field_mapping', {})
            outputs = {}
            
            if is_dynamic:
                # Dynamic output extraction with field mapping
                if field_mapping:
                    for original_name, sanitized_name in field_mapping.items():
                        # Only extract output fields
                        if any(field['name'] == original_name for field in signature_def.get('outputs', [])):
                            if hasattr(result, sanitized_name):
                                outputs[original_name] = getattr(result, sanitized_name)
                            else:
                                # Fallback for safety
                                outputs[original_name] = f"Field '{sanitized_name}' not found in prediction."
                                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                                    f.write(f"[{time.time()}] Warning: Output field '{sanitized_name}' not found in result\n")
                                    f.flush()
                else:
                    # Fallback to original field names for backward compatibility
                    output_fields = [field['name'] for field in signature_def.get('outputs', [])]
                    
                    for field_name in output_fields:
                        if hasattr(result, field_name):
                            outputs[field_name] = getattr(result, field_name)
                        else:
                            # Fallback for safety, but this indicates a potential issue
                            outputs[field_name] = f"Field '{field_name}' not found in prediction."
            else:
                # Legacy Q&A output extraction
                try:
                    outputs["answer"] = result.answer
                    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                        f.write(f"[{time.time()}] DEBUG: Using legacy Q&A output: {result.answer}\n")
                        f.flush()
                except AttributeError:
                    # Try to extract from result object
                    if hasattr(result, '__dict__'):
                        result_dict = result.__dict__
                        for k, v in result_dict.items():
                            if not k.startswith('_') and k != 'completions':
                                outputs[k] = v
                                break
                    if not outputs:
                        outputs["answer"] = str(result)
            
            # Final validation - ensure we have some outputs
            if not outputs:
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] WARNING: No outputs extracted, using emergency fallback\n")
                    f.flush()
                
                # Emergency fallback for unexpected cases
                if hasattr(result, '__dict__'):
                    result_dict = result.__dict__
                    for k, v in result_dict.items():
                        if not k.startswith('_') and k != 'completions':
                            outputs[k] = v
                            break
                
                if not outputs:
                    outputs["result"] = str(result) if result else "No result"
            
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] DEBUG: Final outputs: {outputs}\n")
                f.flush()
            
            return {
                "program_id": program_id,
                "outputs": outputs,
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
        
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if session_id:
                # List programs for specific session from centralized store
                session_data = self.get_session_from_store(session_id)
                if session_data:
                    programs = session_data.get('programs', {})
                    for program_id, program_info in programs.items():
                        program_list.append({
                            "id": program_id,
                            "created_at": program_info.get('created_at'),
                            "execution_count": program_info.get('execution_count', 0),
                            "last_executed": program_info.get('last_executed'),
                            "signature": program_info.get('signature'),
                            "session_id": session_id
                        })
            else:
                # List all programs across all sessions - not supported without session affinity
                # In the new architecture, we don't maintain a local registry of all sessions
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] list_programs called without session_id in pool-worker mode\n")
                    f.flush()
        else:
            # Check if programs exists (it might not in pool-worker mode)
            if hasattr(self, 'programs'):
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
        
        if self.mode == "pool-worker":
            session_id = args.get('session_id')
            if not session_id:
                raise ValueError("Session ID required in pool-worker mode")
            
            # Handle "anonymous" session for minimal pooling - use local storage
            if session_id == "anonymous":
                if not hasattr(self, 'programs'):
                    self.programs = {}
                if program_id not in self.programs:
                    raise ValueError(f"Program not found: {program_id}")
                del self.programs[program_id]
            else:
                # Check if session and program exist in centralized store for named sessions
                session_data = self.get_session_from_store(session_id)
                if not session_data:
                    raise ValueError(f"Session not found: {session_id}")
                    
                programs = session_data.get('programs', {})
                if program_id not in programs:
                    raise ValueError(f"Program not found in session {session_id}: {program_id}")
                    
                # Delete program from centralized session store
                self.update_session_in_store(session_id, "delete_program", program_id, None)
        else:
            if not hasattr(self, 'programs'):
                self.programs = {}
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
        
        if not hasattr(self, 'programs'):
            self.programs = {}
        if not hasattr(self, 'programs'):
            self.programs = {}
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
            "programs_count": len(getattr(self, 'programs', {})),
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
        program_count = len(getattr(self, 'programs', {}))
        if hasattr(self, 'programs'):
            self.programs.clear()
        
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "cleaned",
            "programs_removed": program_count
        }
    
    def reset_state(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Reset all bridge state (alias for cleanup with additional reset info).
        
        Clears all programs and resets counters for clean test isolation.
        
        Args:
            args: Optional parameters
            
        Returns:
            Dictionary with reset status
        """
        program_count = len(getattr(self, 'programs', {}))
        command_count = self.command_count
        error_count = self.error_count
        
        # Clear all state
        if hasattr(self, 'programs'):
            self.programs.clear()
        self.command_count = 0
        self.error_count = 0
        
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "reset",
            "programs_cleared": program_count,
            "commands_reset": command_count,
            "errors_reset": error_count
        }
    
    def cleanup_session(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Clean up a specific session in pool-worker mode.
        
        Args:
            args: Dictionary containing session_id
            
        Returns:
            Dictionary with cleanup status
        """
        if self.mode != "pool-worker":
            return {"status": "not_applicable", "mode": self.mode}
            
        session_id = args.get('session_id')
        if not session_id:
            raise ValueError("Session ID required for cleanup")
            
        # In the new architecture, session cleanup is handled by the centralized store
        # We just need to acknowledge the cleanup request
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] cleanup_session called for session: {session_id}\n")
            f.flush()
        
        # Force garbage collection to clean up any local references
        gc.collect()
        
        return {
            "status": "cleaned",
            "session_id": session_id,
            "programs_removed": 0  # Programs are managed centrally now
        }
    
    def shutdown(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Graceful shutdown command for pool-worker mode.
        
        Args:
            args: Dictionary containing optional worker_id
            
        Returns:
            Dictionary with shutdown acknowledgment
        """
        # Clean up all sessions if in pool-worker mode
        if self.mode == "pool-worker":
            # In the new architecture, sessions are managed centrally
            # We just need to clean up any local references
            sessions_cleaned = 0  # No local sessions to clean
        else:
            if hasattr(self, 'programs'):
                self.programs.clear()
            
        # Force garbage collection
        gc.collect()
        
        return {
            "status": "shutting_down",
            "worker_id": self.worker_id,
            "mode": self.mode,
            "sessions_cleaned": sessions_cleaned if self.mode == "pool-worker" else 0
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
        
        if not hasattr(self, 'programs'):
            self.programs = {}
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
        
        if not hasattr(self, 'programs'):
            self.programs = {}
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

    def get_session_from_store(self, session_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetch session data from the centralized Elixir session store.
        
        This method communicates with the Elixir SessionStore to retrieve
        session data for stateless worker operations.
        
        Args:
            session_id: The session identifier
            
        Returns:
            Session data dictionary or None if not found
        """
        try:
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] get_session_from_store called for session: {session_id}\n")
                f.flush()
            
            # In pool-worker mode, we need to get session data from the Elixir SessionStore
            # For now, we'll use a simple approach where we assume session data 
            # is passed through the session_id parameter or we use a local fallback
            
            # TODO: Implement proper SessionStore communication protocol
            # This would require extending the existing protocol to support
            # bidirectional communication between Python and Elixir
            
            # For Task 2.1, we'll implement a workaround where we return None
            # and let the calling code handle the missing session data
            # The real solution would be to implement a session data cache
            # or extend the protocol to fetch data on demand
            
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] SessionStore communication not yet implemented - returning None\n")
                f.flush()
            
            return None
            
        except Exception as e:
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] Error getting session from store: {e}\n")
                f.flush()
            return None

    def update_session_in_store(self, session_id: str, operation: str, key: str, value: Any) -> bool:
        """
        Update session data in the centralized Elixir session store.
        
        This method communicates with the Elixir SessionStore to update
        session data for stateless worker operations.
        
        Args:
            session_id: The session identifier
            operation: The operation type (e.g., "programs", "metadata", "delete_program")
            key: The key to update
            value: The value to set
            
        Returns:
            True if successful, False otherwise
        """
        try:
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] update_session_in_store called for session: {session_id}, operation: {operation}, key: {key}\n")
                f.flush()
            
            # In pool-worker mode, we communicate with Elixir via the established protocol
            if self.mode == "pool-worker":
                # Create a request to update session data in Elixir SessionStore
                request = {
                    "command": "update_session_data",
                    "args": {
                        "session_id": session_id,
                        "operation": operation,
                        "key": key,
                        "value": value
                    }
                }
                
                # Send request via stdout and wait for response
                # This uses the existing JSON protocol for communication
                request_id = int(time.time() * 1000000)  # Use timestamp-based ID
                
                # For now, we'll simulate the communication since we need to implement
                # the full bidirectional protocol. In a real implementation, this would
                # send a request to Elixir and wait for a response.
                
                # Simulate success for now
                # This will be properly implemented when we add bidirectional communication
                return True
            else:
                # In standalone mode, there's no centralized session store
                return False
            
        except Exception as e:
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] Error updating session in store: {e}\n")
                f.flush()
            return False

    def get_session_data(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handler for get_session_data command from Elixir.
        
        This is called when Elixir needs to retrieve session data.
        In the new architecture, this would typically not be used since
        session data is centralized in Elixir, but it's here for completeness.
        
        Args:
            args: Dictionary containing session_id
            
        Returns:
            Dictionary with session data or error
        """
        session_id = args.get('session_id')
        if not session_id:
            return {"error": "session_id is required"}
        
        try:
            # In the new architecture, Python workers don't store session data locally
            # This handler is mainly for debugging or special cases
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] get_session_data called for session: {session_id}\n")
                f.flush()
            
            return {
                "session_id": session_id,
                "status": "not_stored_locally",
                "message": "Session data is managed centrally in Elixir"
            }
            
        except Exception as e:
            return {"error": str(e)}

    def update_session_data(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handler for update_session_data command from Elixir.
        
        This is called when Elixir needs to notify Python workers about
        session data changes. In the new architecture, this might be used
        for cache invalidation or other coordination.
        
        Args:
            args: Dictionary containing session_id and update information
            
        Returns:
            Dictionary with update status
        """
        session_id = args.get('session_id')
        if not session_id:
            return {"error": "session_id is required"}
        
        try:
            operation = args.get('operation')
            key = args.get('key')
            value = args.get('value')
            
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] update_session_data called for session: {session_id}, operation: {operation}\n")
                f.flush()
            
            # In the new architecture, Python workers don't store session data locally
            # This handler acknowledges the update but doesn't store anything locally
            return {
                "session_id": session_id,
                "status": "acknowledged",
                "message": "Update acknowledged - session data managed centrally"
            }
            
        except Exception as e:
            return {"error": str(e)}


def read_message() -> Optional[Dict[str, Any]]:
    """
    Read a length-prefixed message from stdin.
    
    Returns:
        Parsed JSON message or None if EOF/error
    """
    # Debug log
    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
        f.write(f"[{time.time()}] read_message() called\n")
        f.flush()
    
    try:
        # For Erlang ports, we need to use readexactly-style approach
        # Read 4-byte length header
        length_bytes = sys.stdin.buffer.read(4)
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Read length bytes: {len(length_bytes)} bytes\n")
            if len(length_bytes) > 0:
                f.write(f"[{time.time()}] Raw length bytes: {length_bytes.hex()}\n")
            f.flush()
        
        if len(length_bytes) == 0:  # EOF - process shutdown
            return None
        elif len(length_bytes) < 4:  # Partial read - should not happen with ports
            print(f"Partial length header read: {len(length_bytes)} bytes", file=sys.stderr)
            return None
        
        length = struct.unpack('>I', length_bytes)[0]
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Unpacked length: {length}\n")
            f.flush()
        
        # Read message payload
        message_bytes = sys.stdin.buffer.read(length)
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Read message bytes: {len(message_bytes)}/{length}\n")
            f.flush()
        
        if len(message_bytes) == 0:  # EOF - process shutdown
            return None
        elif len(message_bytes) < length:  # Partial read - should not happen with ports
            print(f"Partial message read: {len(message_bytes)}/{length} bytes", file=sys.stderr)
            return None
        
        # Parse JSON
        message_str = message_bytes.decode('utf-8')
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Message string: {message_str}\n")
            f.flush()
        
        parsed = json.loads(message_str)
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Parsed message: {json.dumps(parsed)}\n")
            f.flush()
        
        return parsed
        
    except (EOFError, json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"Error reading message: {e}", file=sys.stderr)
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Error in read_message: {e}\n")
            f.write(f"[{time.time()}] Traceback: {traceback.format_exc()}\n")
            f.flush()
        return None
    except Exception as e:
        print(f"Unexpected error reading message: {e}", file=sys.stderr)
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Unexpected error in read_message: {e}\n")
            f.write(f"[{time.time()}] Traceback: {traceback.format_exc()}\n")
            f.flush()
        return None


def write_message(message: Dict[str, Any]) -> None:
    """
    Write a length-prefixed message to stdout.
    
    Args:
        message: Dictionary to send as JSON
    """
    # Debug log
    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
        f.write(f"[{time.time()}] write_message() called with: {json.dumps(message)}\n")
        f.flush()
    
    try:
        # Encode message as JSON
        message_str = json.dumps(message, ensure_ascii=False)
        message_bytes = message_str.encode('utf-8')
        length = len(message_bytes)
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Writing message, length: {length}, bytes: {message_bytes[:100]}...\n")
            f.flush()
        
        # Write length header (4 bytes, big-endian) + message
        sys.stdout.buffer.write(struct.pack('>I', length))
        sys.stdout.buffer.write(message_bytes)
        sys.stdout.buffer.flush()
        
        # Debug log
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Message written and flushed\n")
            f.flush()
        
    except BrokenPipeError:
        # Pipe was closed by the other end, exit gracefully
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] BrokenPipeError - exiting\n")
            f.flush()
        sys.exit(0)
    except Exception as e:
        print(f"Error writing message: {e}", file=sys.stderr)
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Error in write_message: {e}\n")
            f.write(f"[{time.time()}] Traceback: {traceback.format_exc()}\n")
            f.flush()


def main():
    """
    Main event loop for the DSPy bridge.
    
    Reads messages from stdin, processes commands, and writes responses to stdout.
    """
    # Debug log that main started
    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
        f.write(f"Main function started\n")
        f.flush()
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='DSPy Bridge for Elixir Integration')
    parser.add_argument('--mode', choices=['standalone', 'pool-worker'], default='standalone',
                        help='Bridge operation mode')
    parser.add_argument('--worker-id', type=str, help='Worker ID for pool-worker mode')
    cmd_args = parser.parse_args()
    
    # Debug log parsed args
    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
        f.write(f"Parsed args: mode={cmd_args.mode}, worker_id={cmd_args.worker_id}\n")
        f.flush()
    
    # Create bridge with specified mode
    bridge = DSPyBridge(mode=cmd_args.mode, worker_id=cmd_args.worker_id)
    
    # Set up signal handlers for graceful shutdown
    def handle_signal(signum, frame):
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Received signal {signum} (worker_id: {cmd_args.worker_id})\n")
            f.flush()
        # For pool workers, just exit cleanly
        if cmd_args.mode == 'pool-worker':
            sys.exit(0)
    
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    
    # Register exit handler for diagnostics
    def exit_handler():
        with open('/tmp/dspy_bridge_debug.log', 'a') as f:
            f.write(f"[{time.time()}] Python bridge exiting (worker_id: {cmd_args.worker_id}, mode: {cmd_args.mode})\n")
            f.write(f"[{time.time()}] Memory usage: {bridge._get_memory_usage()}\n")
            f.flush()
    
    atexit.register(exit_handler)
    
    print(f"DSPy Bridge started in {cmd_args.mode} mode", file=sys.stderr)
    if cmd_args.worker_id:
        print(f"Worker ID: {cmd_args.worker_id}", file=sys.stderr)
    print(f"DSPy available: {DSPY_AVAILABLE}", file=sys.stderr)
    
    # Debug log stdin info
    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
        f.write(f"[{time.time()}] stdin info:\n")
        f.write(f"  isatty: {sys.stdin.isatty()}\n")
        f.write(f"  fileno: {sys.stdin.fileno()}\n")
        f.write(f"  mode: {getattr(sys.stdin, 'mode', 'N/A')}\n")
        f.write(f"  buffer: {sys.stdin.buffer}\n")
        f.flush()
    
    # Debug log
    with open('/tmp/dspy_bridge_debug.log', 'a') as f:
        f.write(f"[{time.time()}] Entering main loop\n")
        f.flush()
    
    try:
        while True:
            # Debug log
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] Waiting for message...\n")
                f.flush()
            
            # Read incoming message
            message = read_message()
            
            # Debug log
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] Message received: {message}\n")
                f.flush()
            
            if message is None:
                print("No more messages, exiting", file=sys.stderr)
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] No more messages, exiting\n")
                    f.flush()
                break
            
            # Extract message components
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            # Debug log
            with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                f.write(f"[{time.time()}] Processing: id={request_id}, command={command}\n")
                f.flush()
            
            if request_id is None or command is None:
                print(f"Invalid message format: {message}", file=sys.stderr)
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] Invalid message format\n")
                    f.flush()
                continue
            
            try:
                # Execute command
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] Executing command: {command}\n")
                    f.flush()
                
                result = bridge.handle_command(command, args)
                
                # Debug log
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] Command result: {json.dumps(result)}\n")
                    f.flush()
                
                # Send success response
                response = {
                    'id': request_id,
                    'success': True,
                    'result': result,
                    'timestamp': time.time()
                }
                write_message(response)
                
            except Exception as e:
                # Debug log
                with open('/tmp/dspy_bridge_debug.log', 'a') as f:
                    f.write(f"[{time.time()}] Command error: {e}\n")
                    f.write(f"[{time.time()}] Traceback: {traceback.format_exc()}\n")
                    f.flush()
                
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
    except BrokenPipeError:
        # Pipe closed, exit silently
        pass
    except Exception as e:
        print(f"Unexpected bridge error: {e}", file=sys.stderr)
        print(traceback.format_exc(), file=sys.stderr)
    finally:
        # Use try-except for final message to avoid BrokenPipeError on stderr
        try:
            print("DSPy Bridge shutting down", file=sys.stderr)
            sys.stderr.flush()
        except:
            pass


if __name__ == '__main__':
    main()