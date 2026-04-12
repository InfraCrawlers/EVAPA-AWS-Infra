import os
import json
import urllib.parse
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

# UPDATED HELPER: Native Python matching to bypass OpenVAS filter bugs
def get_task_id_by_name(gmp, name):
    # Ask for all tasks without using server-side filters
    res = gmp.get_tasks()
    
    # Handle the XML parsing 
    elements = res.xpath('task') if hasattr(res, 'xpath') else res.findall('task')
    
    # Loop through the results and match the name exactly
    for elem in elements:
        elem_name = elem.find('name')
        if elem_name is not None and elem_name.text == name:
            return elem.get('id')
            
    raise ValueError(f"Could not find a task named '{name}'")

def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        
        # Grab the parameter from the URL and decode spaces/special characters
        raw_task_name = path_parameters.get('task_id')
        if not raw_task_name:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing task name in path'})}
            
        task_name = urllib.parse.unquote(raw_task_name)

        with get_gmp_connection() as gmp:
            # Resolve the name to the ID using our bulletproof python-side filter
            task_id = get_task_id_by_name(gmp, task_name)
            
            # Start the scan using the resolved ID
            response = gmp.start_task(task_id)
            
            # Extract the report_id generated for this specific scan run
            report_id = None
            if hasattr(response, 'xpath'):
                report_elem = response.xpath('report_id')
                if report_elem:
                     report_id = report_elem[0].text
            elif isinstance(response, dict):
                report_id = response.get('id')
            
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({
                'message': f'Scan "{task_name}" started successfully',
                'report_id': report_id 
            })
        }
    except ValueError as ve:
        return {'statusCode': 404, 'body': json.dumps({'error': str(ve)})}
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}