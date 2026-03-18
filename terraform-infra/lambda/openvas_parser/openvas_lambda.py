import os
import json
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime
from decimal import Decimal
import boto3

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'openvas-scan-findings')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')

        try:
            print(f"Fetching {key} from bucket {bucket}")
            response = s3.get_object(Bucket=bucket, Key=key)
            xml_content = response['Body'].read()

            root = ET.fromstring(xml_content)
            
            high_severity_vulns = []

            for result in root.findall('.//results/result'):
                severity_text = result.findtext('severity')
                
                if severity_text:
                    try:
                        severity_score = float(severity_text)
                        
                        if severity_score > 7.0:
                            host_elem = result.find('host')
                            host_ip = host_elem.text.strip() if (host_elem is not None and host_elem.text) else 'Unknown'
                            
                            vuln_data = {
                                'vulnerability_name': result.findtext('name', 'Unknown'),
                                'host': host_ip,
                                'port': result.findtext('port', 'Unknown'),
                                'threat_level': result.findtext('threat', 'Unknown'),
                                'cvss_severity': Decimal(str(severity_score)), 
                                'nvt_oid': result.find('nvt').attrib.get('oid', 'Unknown') if result.find('nvt') is not None else 'Unknown'
                            }
                            high_severity_vulns.append(vuln_data)
                            
                    except ValueError:
                        continue


            if high_severity_vulns:
                current_time = datetime.utcnow().isoformat()
                
                item = {
                    'pk': key, 
                    'sk': 'REPORT_DETAILS',
                    'processed_timestamp': current_time,
                    'total_high_severity_count': len(high_severity_vulns),
                    'vulnerabilities': high_severity_vulns
                }

                table.put_item(Item=item)
                print(f"Successfully saved {len(high_severity_vulns)} high severity vulnerabilities for {key} to DynamoDB.")
            else:
                print(f"No high severity vulnerabilities (>7.0) found in report {key}. No DB write performed.")

        except Exception as e:
            print(f"Error processing file {key} from bucket {bucket}. Exception: {str(e)}")
            raise e

    return {
        'statusCode': 200,
        'body': json.dumps('XML processing and DynamoDB upload complete.')
    }