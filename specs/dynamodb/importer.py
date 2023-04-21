import argparse
import base64
import zlib
from pathlib import Path

import boto3
import pandas as pd


def main(csv_file: Path, table_name: str):
    df = pd.read_csv(csv_file)
    data = df.to_dict("records")
    columns = list(df.columns)
    structured_info_columns = columns[:2]
    blob_columns = columns[2:]
    client = boto3.client("dynamodb", region_name="us-east-2")

    try:
        client.delete_table(TableName=table_name)
    except:
        pass

    response = client.create_table(
        TableName=table_name,
        AttributeDefinitions=[
            {
                "AttributeName": "id",
                "AttributeType": "N"
            },
        ],
        ProvisionedThroughput={
            'ReadCapacityUnits': 5,
            'WriteCapacityUnits': 5
        },
        KeySchema=[
            {
                "AttributeName": "id",
                "KeyType": "HASH"
            },
        ])

    for idx, row in enumerate(data):
        payload = {}
        for col in structured_info_columns:
            payload[col] = {"S": str(row[col])}

        for col in blob_columns:
            payload[col] = {"B": base64.b64encode(zlib.compress(str(row[col]).encode("utf-8")))}

        payload["id"] = {"N": str(idx)}
        client.put_item(TableName=table_name, Item=payload)
    print(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(prog="DynamoDBImporter")
    parser.add_argument("--csv_file", type=Path, required=True,
                        help="Path to table cluster specification.")
    parser.add_argument("--table_name", type=str, required=True)
    args = parser.parse_args()
    main(args.csv_file, args.table_name)
