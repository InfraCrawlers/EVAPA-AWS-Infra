def lambda_handler(event, context):
    try:
        query_params = event.get('queryStringParameters') or {}
        search_id = query_params.get('id')

        with get_gmp_connection() as gmp:
            if search_id:
                response = gmp.get_task(task_id=search_id)
            else:
                response = gmp.get_tasks()

            tasks = []
            for item in response.xpath('task'):
                target_elem = item.find('target/name')
                
                # Grab the raw status
                status = item.find('status').text if item.find('status') is not None else 'Unknown'
                
                data = {
                    'id': item.get('id'),
                    'name': item.find('name').text if item.find('name') is not None else '',
                    'status': status,
                    'target_name': target_elem.text if target_elem is not None else 'N/A'
                }
                
                if search_id:
                    progress_elem = item.find('progress')
                    raw_progress = progress_elem.text if progress_elem is not None else '0'
                    
                    # --- SMART PROGRESS LOGIC ---
                    if status == 'Done':
                        clean_progress = '100'
                    elif status in ['New', 'Requested', 'Queued'] or raw_progress == '-1':
                        clean_progress = '0'
                    else:
                        clean_progress = raw_progress
                        
                    data['progress'] = clean_progress
                    
                    report_count_elem = item.find('report_count')
                    scanner_elem = item.find('scanner/name')
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