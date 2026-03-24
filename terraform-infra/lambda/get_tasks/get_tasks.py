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
        search_name = query_params.get('name')

        with get_gmp_connection() as gmp:
            if search_name:
                response = gmp.get_tasks(filter_string=f"name='{search_name}'")
            else:
                response = gmp.get_tasks()

            tasks = []
            for item in response.xpath('task'):
                target_elem = item.find('target/name')
                
                data = {
                    'id': item.get('id'),
                    'name': item.find('name').text if item.find('name') is not None else '',
                    'status': item.find('status').text if item.find('status') is not None else 'Unknown',
                    'target_name': target_elem.text if target_elem is not None else 'N/A'
                }
                
                if search_name:
                    progress_elem = item.find('progress')
                    report_count_elem = item.find('report_count')
                    scanner_elem = item.find('scanner/name')
                    
                    data['progress'] = progress_elem.text if progress_elem is not None else '0'
                    data['report_count'] = report_count_elem.text if report_count_elem is not None else '0'
                    data['scanner_name'] = scanner_elem.text if scanner_elem is not None else 'N/A'

                tasks.append(data)
            
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'tasks': tasks})
        }
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal error', 'details': str(e)})}