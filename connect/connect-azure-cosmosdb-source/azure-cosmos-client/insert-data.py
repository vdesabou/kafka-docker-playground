from azure.cosmos import CosmosClient

import os

url = os.environ['AZURE_COSMOSDB_DB_ENDPOINT_URI']
key = os.environ['AZURE_COSMOSDB_PRIMARY_CONNECTION_KEY']
database_name = os.environ['AZURE_COSMOSDB_DB_NAME']
container_name = os.environ['AZURE_COSMOSDB_CONTAINER_NAME']
client = CosmosClient(url, credential=key)
database = client.get_database_client(database_name)
container = database.get_container_client(container_name)

for i in range(1, 30):
    container.upsert_item({
            'id': 'item{0}'.format(i),
            'productName': 'Widget',
            'productModel': 'Model {0}'.format(i)
        }
    )