"""
DSPex Python Adapters Setup

Installs dspex_adapters as a package so it can be imported
from anywhere in the Python environment.
"""

from setuptools import setup, find_packages

setup(
    name="dspex-adapters",
    version="0.2.1",
    description="DSPy gRPC adapters for DSPex",
    packages=find_packages(),
    python_requires=">=3.9",
    install_requires=[
        "grpcio>=1.60.0",
        "grpcio-tools>=1.60.0",
        "protobuf>=4.25.0",
        "dspy-ai>=2.6.0",
        "litellm>=1.0.0",
    ],
)
