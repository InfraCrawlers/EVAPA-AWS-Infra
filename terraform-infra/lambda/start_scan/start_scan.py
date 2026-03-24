import os
import json
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

@contextmanager
def get_gmp_connection():
    openvas_ip = os.environ['OPENVAS_IP']
    gmp_user = os.environ['GMP_USER']
    gmp_password = os.environ['GMP_PASSWORD']
    
    connection = TLSConnection(hostname=openvas_ip, port=9390)
    transform = EtreeTransform()
    
    with Gmp(connection=connection, transform=transform) as gmp:
        gmp.authenticate(gmp_user, gmp_password)
        yield gmp

def lambda_handler(event, context):
    try:
        # Extract task_id from the API Gateway path parameters
        path_parameters = event.get('pathParameters') or {}
        task_id = path_parameters.get('task_id')

        if not task_id:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing task_id in path parameters'})}

        with get_gmp_connection() as gmp:
            response = gmp.start_task(task_id)
            report_id = response.get('id')
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Scan started successfully',
                'report_id': report_id 
            })
        }
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}