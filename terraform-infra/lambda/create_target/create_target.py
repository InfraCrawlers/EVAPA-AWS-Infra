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
        body = json.loads(event.get('body', '{}'))
        name = body.get('name')
        hosts = body.get('hosts')
        port_list_id = body.get('port_list_id')

        if not all([name, hosts, port_list_id]):
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing name, hosts, or port_list_id'})}

        with get_gmp_connection() as gmp:
            response = gmp.create_target(
                name=name,
                hosts=hosts,
                port_list_id=port_list_id
            )
            target_id = response.get('id')
            
        return {
            'statusCode': 200,
            'body': json.dumps({'target_id': target_id})
        }
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}