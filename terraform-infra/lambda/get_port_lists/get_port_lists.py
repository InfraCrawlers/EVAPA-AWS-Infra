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
                # 2. Use the direct ID lookup method
                response = gmp.get_port_list(port_list_id=search_id)
            else:
                # Get all if no ID is provided
                response = gmp.get_port_lists()

            port_lists = []
            for item in response.xpath('port_list'):
                data = {
                    'id': item.get('id'),
                    'name': item.find('name').text if item.find('name') is not None else '',
                    'port_count': item.find('port_count').text if item.find('port_count') is not None else '0'
                }
                
                # If a specific ID was requested, pull the exact port ranges
                if search_id:
                    ranges = []
                    for pr in item.xpath('port_ranges/port_range'):
                        ranges.append(pr.text if pr.text else '')
                    data['port_ranges'] = ranges
                    
                port_lists.append(data)
            
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'port_lists': port_lists})
        }
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal error', 'details': str(e)})}