#!/bin/bash

databricks configure

catalogs=$(databricks catalogs list | awk '{print $1}')
for catalog in $catalogs; do
  if [ "$catalog" != "Name" ]; then
        echo "Catalog: $catalog"
  fi
done

echo $(databricks warehouses list)
