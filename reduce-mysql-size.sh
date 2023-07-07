#!/bin/bash
# reduce mysql size
# @Author: Firstname Lastname   <https://github.com/robertdavidgraham>
# @license MIT <https://opensource.org/licenses/MIT>

# sed -i "s/'--log_bin_trust_function_creators=1'/'--log_bin_trust_function_creators=1', '--innodb_file_per_table=1'/" docker-compose.yml 

# bin/start --build --force_recreate


<<\SCRIPT tee ./bin/dbcleanup > /dev/null
#!/bin/bash

source env/db.env
################## Function ###############################
# Function to get query command
get_query_command(){
  local table_name=$1
  local id=$2

  if [ $# -lt 3 ]; then
    row_limit=10
  else
    row_limit=$3
  fi
  result="DELETE record FROM $table_name AS record 
              LEFT JOIN 
                (SELECT $id FROM $table_name 
                ORDER BY $id DESC LIMIT $row_limit) AS record2 
              ON record.$id = record2.$id 
            WHERE record2.$id IS NULL;"
  echo "$result"
}

delete_records_table() {
  local table_name=$1
  local id=$2
  local row_limit=$3

  if [[ $3 = "" ]]; then
    row_limit=10
  else
    row_limit=$3
  fi
 
  query=$(get_query_command "$table_name" "$id" "$row_limit")

  # Call execute_sql_query function
  execute_sql_query "$query" "$table_name"
}
# Function to delete records from a table
delete_records() {
  local table_name=$1
  local row_limit=$2

  declare -A foreignKeyTables=(
    ["customer_entity"]="entity_id "
    ["customer_grid_flat"]="entity_id"
    ["quote"]="entity_id"
    ["quote_item"]="item_id"
    ["quote_address"]="address_id"
    ["quote_payment"]="payment_id"
    ["quote_shipping_rate"]="rate_id"
    ["sales_order"]="entity_id"
    ["sales_order_item"]="item_id"
    ["sales_order_address"]="entity_id"
    ["sales_order_payment"]="entity_id"
    ["sales_order_grid"]="entity_id"
    ["sales_creditmemo_grid"]="entity_id"
    ["sales_invoice_grid"]="entity_id"
    ["sales_shipment_grid"]="entity_id"
  )
  # Check if the table is constrained by foreign keys
  check=0
  for foreignKeyTable in "${!foreignKeyTables[@]}"; do
    if [[ $foreignKeyTable == "$table_name" ]]; then
      check+=1
    fi
  done

  if [[ $check > 0 ]]; then
    for foreignKeyTable in "${!foreignKeyTables[@]}"; do
      if [[ $foreignKeyTable == "$table_name" ]]; then
        if [[ $row_limit == "" ]]; then
          query=$(get_query_command "$table_name" "${foreignKeyTables[$foreignKeyTable]}")
        else 
          if [[ $row_limit =~ ^[0-9]+$ ]]; then
            query=$(get_query_command "$table_name" "${foreignKeyTables[$foreignKeyTable]}" "$row_limit")
          else
            echo "please enter the number of records you want to keep!"
            exit 1
          fi
        fi
      fi
    done
  else
    query="TRUNCATE TABLE $table_name;"
  fi
  # Call execute_sql_query function
  execute_sql_query "$query" "$table_name"
}

# Function to execute the SQL query using bin/mysql
execute_sql_query() {
  local query="SET FOREIGN_KEY_CHECKS = 1; $1"
  local table_name=$2
  # Execute query
  echo "$query"
  echo "########################################"
  # result=$(bin/mysql -e "$query" 2>&1)

  if [ $? -eq 0 ]; then
    echo "Cleanup $table_name successful!"
  else
    echo "Cleanup failed. Error message:"
    echo "$result"
  fi
}

####################### Main script ######################

if [ $# -lt 1 ]; then
  echo "Please provide table name as parameter."
  exit 1
fi
# Get the table name from the first parameter 
group_name="$1"

if [ $# -lt 2 ]; then
  row_limit=""
else
  row_limit=$2
fi
# Define table groups
declare -A table_groups=(
  ["catalog"]="catalog_compare_item"
  ["session"]="session persistent_session admin_user_session"
  ["report"]="report_compared_product_index report_event report_viewed_product_index report_viewed_product_aggregated_daily report_viewed_product_aggregated_monthly report_viewed_product_aggregated_yearly"
  ["log"]="customer_log customer_visitor"
  ["customer"]="customer_entity customer_grid_flat"
  ["quote"]="quote quote_item quote_address quote_payment quote_shipping_rate"
  ["salesorder"]="sales_order sales_order_item sales_order_address sales_order_payment"
  ["salesgrid"]="sales_order_grid sales_creditmemo_grid sales_invoice_grid sales_shipment_grid"
)

# Check if the table group is "all"
if [ "$group_name" = "all" ]; then
  tables=""
  for category_tables in "${table_groups[@]}"; do
    tables+=" $category_tables"
  done
else 
  tables="${table_groups[$group_name]}"
fi

# Check if the table group exists
if [ -z "$tables" ]; then
  result=$(bin/mysql -e "SHOW TABLES LIKE '$group_name';" | grep $group_name)
  if [ -z "$result" ]; then
    # Separate input parameter into array by ","
    IFS=',' read -ra TABLES <<< "$1"
    for table in "${TABLES[@]}"; do
      # check the table exists or not
      result=$(bin/mysql -e "SHOW TABLES LIKE '$table';" | grep $table)
      if [ -z "$result" ]; then
        echo "Table $table does not exist. Skipping..."
      else
        # get primary key from input table name
        PRIMARY_KEY=$(bin/mysql -sN -e "SELECT COLUMN_NAME
                      FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
                      WHERE TABLE_SCHEMA = '${MYSQL_DATABASE}' AND TABLE_NAME = '$table' AND CONSTRAINT_NAME = 'PRIMARY'")
        # call delete function for table
        delete_records_table "$table" "$PRIMARY_KEY" "$row_limit"
      fi
    done
  else
    # get primary key from input table name
    PRIMARY_KEY=$(bin/mysql -sN -e "SELECT COLUMN_NAME
                  FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
                  WHERE TABLE_SCHEMA = '${MYSQL_DATABASE}' AND TABLE_NAME = '$group_name' AND CONSTRAINT_NAME = 'PRIMARY'")
    # call delete function for table
    delete_records_table "$group_name" "$PRIMARY_KEY" "$row_limit"
  fi
else
  for table in $tables; do
    result=$(bin/mysql -e "SHOW TABLES LIKE '$table';" | grep $table)
    if [ -z "$result" ]; then
      echo "Table $table does not exist. Skipping..."
    else
      delete_records "$table" "$row_limit"
    fi
  done
fi
SCRIPT

chmod u+x bin/dbcleanup

# bin/mysqldump | gzip -9 -c > ~/backups/db.sql.gz
# 
source env/db.env
bin/cli mysqldump -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -h"${MYSQL_HOST}" "${MYSQL_DATABASE}" --no-tablespaces --routines --force --triggers --single-transaction --opt --skip-lock-tables | sed -e 's/DEFINER[ ]*=[ ]*[^*]*\*/\*/' | gzip -9 -c > ~/backups/db.sql.gz

# restore
# source env/db.env
# zcat ~/backups/db.sql.gz | bin/clinotty mysql -h"${MYSQL_HOST}" -uroot -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}"


# import db 
# setting up normally
# check db docker container size 
# backup db >> mysqldyump
# run dbcleanup
# recheck db docker container size 
# conclusion

# bash -c "$(curl -fsSL https://raw.githubusercontent.com/phamtung-23/script_cleanup_database/main/reduce-mysql-size.sh)"