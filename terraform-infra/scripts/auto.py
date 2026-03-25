import os
import json
import boto3
from lxml import etree
from gvm.connections import UnixSocketConnection
from gvm.protocols.latest import Gmp
from gvm.transforms import EtreeCheckCommandTransform

BUCKET_NAME = "capstone-vuln-mgmt-openvas-reports"
STATE_FILE = "/opt/openvas_scripts/sent_reports.json"
GVM_SOCKET_PATH = "/var/lib/docker/volumes/greenbone-community-edition_gvmd_socket_vol/_data/gvmd.sock"
S3_FOLDER = "openvas-reports/"

s3_client = boto3.client('s3')

def get_already_sent():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return []
    return []

def mark_as_sent(report_id):
    sent = get_already_sent()
    if report_id not in sent:
        sent.append(report_id)
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump(sent, f)

def download_and_upload_report(report_id):

    connection = UnixSocketConnection(path=GVM_SOCKET_PATH, timeout=300)
    transform = EtreeCheckCommandTransform()

    with Gmp(connection=connection, transform=transform) as gmp:
        gmp.authenticate("admin", "admin")

        XML_FORMAT_ID = "a994b278-1f62-11e1-96ac-406186ea4fc5"
        CUSTOM_FILTER = "apply_overrides=0 min_qod=70 sort-reverse=severity rows=-1"

        full_report_response = gmp.get_report(
            report_id=report_id,
            report_format_id=XML_FORMAT_ID,
            filter_string=CUSTOM_FILTER,
            ignore_pagination=True
        )

        report_content = etree.tostring(full_report_response, pretty_print=True)
        target_key = f"{S3_FOLDER}{report_id}.xml"

        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=target_key,
            Body=report_content
        )

        mark_as_sent(report_id)
        print(f"SUCCESS: Uploaded {target_key} to S3 bucket {BUCKET_NAME}")


def run_sync():
    if not os.path.exists(GVM_SOCKET_PATH):
        print(f"Error: OpenVAS socket not found at {GVM_SOCKET_PATH}")
        return

    list_connection = UnixSocketConnection(path=GVM_SOCKET_PATH, timeout=60)
    list_transform = EtreeCheckCommandTransform()

    with Gmp(connection=list_connection, transform=list_transform) as gmp:
        gmp.authenticate("admin", "admin")
        reports_xml = gmp.get_reports(ignore_pagination=True)

    sent_ids = get_already_sent()

    for report in reports_xml.xpath('//report'):
        report_id = report.get('id')

        if not report_id:
            continue

        task_name_list = report.xpath('./task/name/text()')
        task_name = task_name_list[0] if task_name_list else "Unknown_Task"

        status_list = report.xpath('./scan_run_status/text()')
        status = status_list[0] if status_list else "Unknown"

        if status != "Done":
            print(f"Skipping report {report_id} from task '{task_name}' - Status is '{status}' (Waiting for 'Done')")
            continue

        if report_id not in sent_ids:
            print(f"Found new finished report from task '{task_name}': {report_id}. Downloading content...")
            try:
                download_and_upload_report(report_id)
            except Exception as e:
                print(f"Error during report processing for {report_id}: {e}")



if __name__ == "__main__":
    print("--- Starting OpenVAS to S3 Sync ---")
    run_sync()
    print("--- Sync process finished ---")