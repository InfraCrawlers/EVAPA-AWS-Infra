import os
import json
import enum
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

# The Ultimate Bulletproof AliveTest Import
# Greenbone aggressively moves this Enum between GMP version files.
# We try the specific version modules, and if all else fails, 
# we build a perfect mock Enum that bypasses their strict type-check.
try:
    from gvm.protocols.gmpv224 import AliveTest
except ImportError:
    try:
        from gvm.protocols.gmpv225 import AliveTest
    except ImportError:
        try:
            from gvm.protocols.gmpv226 import AliveTest
        except ImportError:
            class AliveTest(enum.Enum):
                CONSIDER_ALIVE = "Consider Alive"
                SCAN_CONFIG_DEFAULT = "Scan Config Default"

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

# Helper to find an ID by Name
def get_id_by_name(gmp, entity_type, name):
    res = gmp.get_port_lists(filter_string=f"name='{name}'")
    # Handle both lxml (xpath) and standard xml (findall)
    elements = res.xpath('port_list') if hasattr(res, 'xpath') else res.findall('port_list')
    if not elements:
        raise ValueError(f"Could not find a {entity_type} named '{name}'")
    return elements[0].get('id')

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        name = body.get('name')
        hosts = body.get('hosts')
        port_list_name = body.get('port_list_name') 
        
        # Parse the string into the specific Enum object python-gvm demands
        alive_test_input = body.get('alive_test', 'Consider Alive')
        
        if alive_test_input == 'Consider Alive':
            enum_val = AliveTest.CONSIDER_ALIVE
        elif alive_test_input == 'Scan Config Default':
            enum_val = AliveTest.SCAN_CONFIG_DEFAULT
        else:
            enum_val = AliveTest.CONSIDER_ALIVE

        if not all([name, hosts, port_list_name]):
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing name, hosts, or port_list_name'})}

        with get_gmp_connection() as gmp:
            # Resolve the name to an ID first
            port_list_id = get_id_by_name(gmp, 'port_list', port_list_name)
            
            # Pass the precise Enum object (whether real or mocked)
            response = gmp.create_target(
                name=name,
                hosts=hosts,
                port_list_id=port_list_id,
                alive_test=enum_val 
            )
            target_id = response.get('id')
            
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'Target created', 'target_id': target_id})
        }
    except ValueError as ve:
        return {'statusCode': 404, 'body': json.dumps({'error': str(ve)})}
    except GvmError as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}