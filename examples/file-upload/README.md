# File Upload Demo

Demonstrates file upload and download functionality in vxui applications.

## Features

- **File Upload**: Upload files via browser
- **Base64 Encoding**: File data encoded for WebSocket transmission
- **File Storage**: Save uploaded files to disk
- **File Listing**: Display uploaded files with metadata
- **File Download**: Download previously uploaded files
- **Drag & Drop**: Modern file upload interface

## How to Run

```sh
# From this directory
v run main.v
```

Or build and run:

```sh
v -prod -o file-upload main.v
./file-upload
```

## What It Demonstrates

This example shows how to:
- Handle file uploads through WebSocket
- Use base64 encoding for binary data transmission
- Manage file storage and retrieval
- Display file metadata (name, size, type)
- Implement download functionality
- Work with temporary directories

## Architecture

1. **Upload**: File is read by browser, base64 encoded, sent via WebSocket
2. **Storage**: Backend decodes and saves to temp directory
3. **Listing**: Files displayed with size, type, and upload time
4. **Download**: File read from disk and sent back to browser

## Security Note

This demo stores files in a temporary directory. In production, implement:
- File type validation
- File size limits
- Virus scanning
- Secure storage location
