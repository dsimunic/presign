# Presign Tool Examples

This directory contains example scripts that demonstrate the functionality of the `presign` tool for generating Amazon S3 presigned URLs.

## Prerequisites

1. Build the presign tool: `make` from the repository root
2. Configure credentials and S3 settings in `../secrets-s3.env`
3. Install `curl` for testing actual S3 operations

## Configuration

All scripts source `../secrets-s3.env` which should contain:
```bash
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
S3_REGION=your_region
S3_ENDPOINT=https://s3.your-region.provider.com
BUCKET=your-bucket-name
```

Scripts pass the bucket name and object key together to `presign` (for example `"$BUCKET/path/to/object"`).
If you prefer to set per-invocation values instead of using environment defaults, supply the region and
endpoint on the command line following the updated syntax:

```bash
presign s3 METHOD [REGION] [ENDPOINT] bucket/key EXPIRE_MIN
```

## Basic Examples

### Simple URL Generation

- **`basic-get.sh`** - Generate a presigned URL for downloading a file
- **`basic-put.sh`** - Generate a presigned URL for uploading a file with Content-Type
- **`basic-delete.sh`** - Generate a presigned URL for deleting a file

### Advanced Features

- **`advanced-put.sh`** - Upload with multiple headers and metadata
- **`special-characters.sh`** - Handle paths with spaces and special characters
- **`time-override.sh`** - Use custom timestamps with the `--now` option

## Full S3 Integration Tests

These scripts actually interact with your S3 bucket:

- **`full-upload-test.sh`** - Create and upload a real file to S3
- **`full-download-test.sh`** - Download a file from S3 (specify path as argument)
- **`full-delete-test.sh`** - Delete a file from S3 (requires confirmation)
- **`complete-workflow.sh`** - Full lifecycle: upload → download → verify → delete

## Usage

Make all scripts executable:
```bash
chmod +x *.sh
```

Run basic examples (no S3 interaction):
```bash
./basic-get.sh
./basic-put.sh
./advanced-put.sh
```

Run full integration tests (requires valid S3 credentials):
```bash
./full-upload-test.sh          # Upload a test file
./complete-workflow.sh         # Complete upload/download/delete cycle
```


## Expected Output

Basic examples output presigned URLs that you can use with curl.
Integration tests show complete HTTP interactions with status codes and verification steps.

## Safety Notes

- Integration tests create temporary objects with timestamp-based names
- Delete tests require confirmation before proceeding
- All test objects are created under `test-*` prefixes for easy identification
