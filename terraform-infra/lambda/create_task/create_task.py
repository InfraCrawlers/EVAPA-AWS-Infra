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

# Updated Helper to find IDs by Name natively in Python
def get_id_by_name(gmp, entity_type, name):
    # Ask for all items without using server-side filters
    if entity_type == 'target':
        res = gmp.get_targets()
    elif entity_type == 'config':
        res = gmp.get_scan_configs()
    elif entity_type == 'scanner':
        res = gmp.get_scanners()
        
    elements = res.xpath(entity_type) if hasattr(res, 'xpath') else res.findall(entity_type)
    
    # Loop through the results and match the name exactly
    for elem in elements:
        elem_name = elem.find('name')
        if elem_name is not None and elem_name.text == name:
            return elem.get('id')
            
    raise ValueError(f"Could not find a {entity_type} named '{name}'")

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        name = body.get('name')
        target_name = body.get('target_name')
        
        # Smart Defaults - if frontend doesn't provide these, use the standards
        config_name = body.get('config_name', 'Full and fast')
        scanner_name = body.get('scanner_name', 'OpenVAS Default')

        if not all([name, target_name]):
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing name or target_name'})}

        with get_gmp_connection() as gmp:
            # Resolve all names to their hidden UUIDs
            target_id = get_id_by_name(gmp, 'target', target_name)
            config_id = get_id_by_name(gmp, 'config', config_name)
            scanner_id = get_id_by_name(gmp, 'scanner', scanner_name)

            response = gmp.create_task(
                name=name,
                target_id=target_id,
                config_id=config_id,
                scanner_id=scanner_id
            )
            task_id = response.get('id')
            
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'Task created', 'task_id': task_id})
        }
    except ValueError as ve:
        return {'statusCode': 404, 'body': json.dumps({'error': str(ve)})}
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}