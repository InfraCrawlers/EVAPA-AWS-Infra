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
        query_params = event.get('queryStringParameters') or {}
        # 1. Grab 'id' from the query string instead of 'name'
        search_id = query_params.get('id')

        with get_gmp_connection() as gmp:
            if search_id:
                # 2. Use the direct ID lookup method for targets
                response = gmp.get_target(target_id=search_id)
            else:
                # Get all if no ID is provided
                response = gmp.get_targets()

            targets = []
            for item in response.xpath('target'):
                port_list_elem = item.find('port_list/name')
                
                data = {
                    'id': item.get('id'),
                    'name': item.find('name').text if item.find('name') is not None else '',
                    'port_list_name': port_list_elem.text if port_list_elem is not None else 'N/A'
                }
                
                # If a specific ID was requested, pull the advanced host details
                if search_id:
                    data['hosts'] = item.find('hosts').text if item.find('hosts') is not None else ''
                    data['exclude_hosts'] = item.find('exclude_hosts').text if item.find('exclude_hosts') is not None else ''
                    data['max_hosts'] = item.find('max_hosts').text if item.find('max_hosts') is not None else '1'
                    
                targets.append(data)
            
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'targets': targets})
        }
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal error', 'details': str(e)})}