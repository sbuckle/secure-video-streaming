import datetime
import json
import os
import base64
import boto3

from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import padding

from botocore.signers import CloudFrontSigner

CF_KEY_ID = os.environ.get('CF_KEY_ID')
CF_URL = os.environ.get('CF_URL')
SM_SECRET_NAME = os.environ.get('SM_SECRET_NAME')

required_vars = [CF_KEY_ID, CF_URL, SM_SECRET_NAME]

if not all(required_vars):
    raise KeyError(
        f'Missing required environment variable/s. Required vars {str(required_vars)}.')

client = boto3.client('secretsmanager')
cf_private_key_base64 = client.get_secret_value(
    SecretId=SM_SECRET_NAME)['SecretString']


def rsa_signer(message):
    private_key = serialization.load_pem_private_key(
        base64.b64decode(cf_private_key_base64),
        password=None
    )
    return private_key.sign(message, padding.PKCS1v15(), hashes.SHA1())


cf_signer = CloudFrontSigner(CF_KEY_ID, rsa_signer)


def lambda_handler(event, context):
    movie_id = event['queryStringParameters'].get('movie')

    if movie_id is None:
        # or handle otherwise when required query param is missing
        return {'statusCode': 400, 'body': ''}

    movie_path = 'movies/movie_' + movie_id + "/index.m3u8"
    # if  movie_path starts with '/', remove it.
    movie_path = movie_path[1:] if movie_path[0] == '/' else movie_path
    movie_folder_path = '/'.join(movie_path.split('/')[:-1])

    try:
        # if CF_URL ends with '/', remove it.
        url = CF_URL[:-1] if CF_URL[-1:] == '/' else CF_URL
        full_url = '/'.join([url, movie_path])
        # if movie_folder_path = '', don't join with '/'
        uri = str('' if movie_folder_path ==
                  '' else '/').join([movie_folder_path, '*'])
        resource = '/'.join([url, uri])

        # Hardcoded for simplicity. It can be dynamic value that's retrieved from another source.
        expire_token_in_hours = 6

        current_time = datetime.datetime.utcnow()
        expire_date = current_time + \
            datetime.timedelta(hours=expire_token_in_hours)

        policy = {
            "Statement": [
                {
                    "Resource": resource,
                    "Condition": {
                        "DateLessThan": {
                            "AWS:EpochTime": int(expire_date.timestamp())
                        }
                    }
                }
            ]
        }

        policy_json_str = json.dumps(policy)
        signed_url = cf_signer.generate_presigned_url(
            full_url, policy=policy_json_str)

        return {
            'statusCode': 200,
            'body': signed_url
        }
    except Exception as e:
        print(e)

    return {'statusCode': 500, 'body': ''}
