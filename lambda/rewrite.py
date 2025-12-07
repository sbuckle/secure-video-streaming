import boto3
import os

KEY_PREFIX = os.environ.get('KEY_PREFIX')
S3_BUCKET = os.environ.get('S3_BUCKET')
SEGMENT_FILE_EXT = os.environ.get('SEGMENT_FILE_EXT', '.ts')

required_vars = [KEY_PREFIX, S3_BUCKET]
if not all(required_vars):
    raise KeyError(
        f'Missing required environment variable/s. Required vars {required_vars}.')

s3 = boto3.client('s3')


def lambda_handler(event, context):
    try:
        s3_key = event['pathParameters']['proxy']
        obj = s3.get_object(Bucket=S3_BUCKET, Key=s3_key)

        body = obj['Body'].read().decode('utf-8')
        qp = event['queryStringParameters']

        params = ['?']
        # reconstruct query param uri
        [(params.append(p.replace(KEY_PREFIX, '') + '=' + qp[p] + "&"))
         for p in qp if KEY_PREFIX in p]
        sign_params = ''.join(params).rstrip("&")

        # append query params to each segment
        resp_body = body.replace(SEGMENT_FILE_EXT, ''.join(
            [SEGMENT_FILE_EXT, sign_params]))

        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/vnd.apple.mpegurl'},
            'body': resp_body
        }
    except Exception as e:
        print(e)

    return {'statusCode': 500, 'body': ''}
