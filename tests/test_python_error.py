#!/usr/bin/env python3
"""
Test script to generate Python stack traces for testing hyperlink functionality.
This script is used to verify that TermLet correctly detects and makes clickable
the file references in Python tracebacks.
"""


def inner_function():
    """Function that raises an error."""
    raise ValueError("Test error from inner function")


def middle_function(data):
    """Function that calls inner_function."""
    if data is None:
        inner_function()
    return data * 2


def outer_function():
    """Function that calls middle_function with None."""
    result = middle_function(None)
    return result


def test_type_error():
    """Test function that causes a TypeError."""
    x = None
    return x['key']  # This will raise TypeError


def test_index_error():
    """Test function that causes an IndexError."""
    items = [1, 2, 3]
    return items[10]  # This will raise IndexError


def test_attribute_error():
    """Test function that causes an AttributeError."""
    obj = None
    return obj.some_method()  # This will raise AttributeError


if __name__ == "__main__":
    import sys

    print("Python Stack Trace Test Script")
    print("=" * 50)

    if len(sys.argv) > 1:
        test_type = sys.argv[1]
    else:
        test_type = "value"

    print(f"Running test: {test_type}")
    print()

    try:
        if test_type == "value":
            outer_function()
        elif test_type == "type":
            test_type_error()
        elif test_type == "index":
            test_index_error()
        elif test_type == "attr":
            test_attribute_error()
        else:
            print(f"Unknown test type: {test_type}")
            print("Available types: value, type, index, attr")
            sys.exit(1)
    except Exception as e:
        # Let the exception propagate to show the full traceback
        raise
