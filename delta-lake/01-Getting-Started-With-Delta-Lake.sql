-- Databricks notebook source
-- MAGIC %python
-- MAGIC dbutils.widgets.dropdown("reset_all_data", "false", ["true", "false"], "Reset all data")

-- COMMAND ----------

-- MAGIC %md-sandbox
-- MAGIC
-- MAGIC # Getting started with Delta Lake
-- MAGIC
-- MAGIC <img src="https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-logo-whitebackground.png" style="width:200px; float: right"/>
-- MAGIC
-- MAGIC [Delta Lake](https://delta.io/) is an open storage format used to save your data in your Lakehouse. Delta provides an abstraction layer on top of files. It's the storage foundation of your Lakehouse.
-- MAGIC
-- MAGIC In this notebook, we will explore Delta Lake main capabilities, from table creation to time travel.
-- MAGIC
-- MAGIC <!-- Collect usage data (view). Remove it to disable collection. View README for more details.  -->
-- MAGIC <img width="1px" src="https://ppxrzfxige.execute-api.us-west-2.amazonaws.com/v1/analytics?category=data-engineering&org_id=3488470091230896&notebook=%2F01-Getting-Started-With-Delta-Lake&demo_name=delta-lake&event=VIEW&path=%2F_dbdemos%2Fdata-engineering%2Fdelta-lake%2F01-Getting-Started-With-Delta-Lake&version=1">

-- COMMAND ----------

-- DBTITLE 1,Init the demo data under ${raw_data_location}/user_parquet.
-- MAGIC %run ./_resources/00-setup $reset_all_data=$reset_all_data

-- COMMAND ----------

-- MAGIC %python
-- MAGIC #For this demo, We'll use a synthetic dataset containing user information, saved under ${raw_data_location}/user_parquet.
-- MAGIC print(f"Our user dataset is stored under raw_data_location={raw_data_location}/user_parquet")
-- MAGIC dbutils.widgets.text("raw_data_location", raw_data_location)

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{raw_data_location}/"))

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{raw_data_location}/user_parquet/"))

-- COMMAND ----------

-- MAGIC %md ## ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Creating our first Delta Lake table
-- MAGIC
-- MAGIC Delta is the default file and table format using Databricks. You are likely already using delta without knowing it!
-- MAGIC
-- MAGIC Let's create a few table to see how to use Delta:

-- COMMAND ----------

-- DBTITLE 1,Create Delta table using SQL
-- Creating our first Delta table
CREATE TABLE IF NOT EXISTS user_delta (id BIGINT, creation_date TIMESTAMP, firstname STRING, lastname STRING, email STRING, address STRING, gender INT, age_group INT);

-- Let's load some data in this table
COPY INTO user_delta FROM '${raw_data_location}/user_parquet' FILEFORMAT = parquet;

SELECT * FROM user_delta;

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC
-- MAGIC That's it! Our Delta table is ready and you get all the Delta Benefits. 
-- MAGIC
-- MAGIC Using Delta is that simple!
-- MAGIC
-- MAGIC Let's see how we can use Python or scala API to do the same:

-- COMMAND ----------

-- DBTITLE 1,Create Delta table using python / Scala API
-- MAGIC %python
-- MAGIC data_parquet = spark.read.parquet(raw_data_location+"/user_parquet")
-- MAGIC
-- MAGIC data_parquet.write.format("delta").mode("overwrite").save(raw_data_location+"/user_delta")
-- MAGIC
-- MAGIC display(spark.read.load(raw_data_location+"/user_delta"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Upgrading an existing Parquet or Iceberg table to Delta Lake
-- MAGIC It's also very simple to migrate an existing Parquet or Iceberg table to Delta Lake. Here is an example: 
-- MAGIC
-- MAGIC ```
-- MAGIC CONVERT TO DELTA database_name.table_name; -- only for Parquet tables
-- MAGIC
-- MAGIC CONVERT TO DELTA parquet.`s3://my-bucket/path/to/table`
-- MAGIC   PARTITIONED BY (date DATE); -- if the table is partitioned
-- MAGIC
-- MAGIC CONVERT TO DELTA iceberg.`s3://my-bucket/path/to/table`; -- uses Iceberg manifest for metadata
-- MAGIC ```

-- COMMAND ----------

-- DBTITLE 1,Creating a copy of the parquet file
-- MAGIC %python
-- MAGIC dbutils.fs.cp(f"{raw_data_location}/user_parquet/", f"{raw_data_location}/user_parquet_2/", True)

-- COMMAND ----------

-- DBTITLE 1,Check the content of the cloned folder
-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{raw_data_location}/user_parquet_2"))

-- COMMAND ----------

-- DBTITLE 1,Converting parquet to Delta
CONVERT TO DELTA parquet.`dbfs:/Users/andras.csillag@databricks.com/demos/retail/delta/user_parquet_2/`

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls(f"{raw_data_location}/user_parquet_2/_delta_log"))

-- COMMAND ----------

-- DBTITLE 1,Query the table as delta
SELECT * FROM DELTA.`dbfs:/Users/andras.csillag@databricks.com/demos/retail/delta/user_parquet_2/`

-- COMMAND ----------

-- MAGIC %md ## ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Delta Lake for Batch and Streaming operations
-- MAGIC
-- MAGIC Delta makes it super easy to work with data stream. 
-- MAGIC
-- MAGIC In this example, we'll create a streaming query on top of our table, and add data in the table. The stream will pick the changes without any issue.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC # Read the insertion of data
-- MAGIC spark.readStream.option("ignoreDeletes", "true").option("ignoreChanges", "true").table("user_delta").createOrReplaceTempView("user_delta_readStream")

-- COMMAND ----------

select gender, round(avg(age_group),2) from user_delta_readStream group by gender

-- COMMAND ----------

-- MAGIC %md **Wait** until the stream is up and running before executing the code below

-- COMMAND ----------

-- DBTITLE 1,Let's add a new user, it'll appear in our previous aggregation as the stream picks up the update
insert into user_delta (id, creation_date, firstname, lastname, email, address, gender, age_group) 
    values (99999, now(), 'Quentin', 'Ambard', 'quentin.ambard@databricks.com', 'FR', '2', 3) 

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ##![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Full DML Support
-- MAGIC
-- MAGIC Delta Lake supports standard DML including UPDATE, DELETE and MERGE INTO, providing developers more controls to manage their big datasets.

-- COMMAND ----------

-- Running `UPDATE` on the Delta Lake table
UPDATE user_delta SET age_group = 4 WHERE id = 99999

-- COMMAND ----------

DELETE FROM user_delta WHERE id > 10

-- COMMAND ----------

-- DBTITLE 1,UPSERT: update if exists, insert otherwise
-- Let's create a table containing a list of changes we want to apply to the user table (ex: CDC flow)
create table if not exists user_updates 
  (id bigint, creation_date TIMESTAMP, firstname string, lastname string, email string, address string, gender int, age_group int);
  
delete from user_updates;

insert into user_updates values (1,     now(), 'Marco',   'polo',   'marco@polo.com',    'US', 2, 3); 
insert into user_updates values (2,     now(), 'John',    'Doe',    'john@doe.com',      'US', 2, 3);
insert into user_updates values (99999, now(), 'Quentin', 'Ambard', 'qa@databricks.com', 'FR', 2, 3);
select * from user_updates;

-- COMMAND ----------

select * from user_delta where id in (1 ,2, 99999)

-- COMMAND ----------

-- We can now MERGE the changes into our main table (note: we could also DELETE the rows based on a predicate)
MERGE INTO user_delta as d USING user_updates as m
  ON d.id = m.id
  WHEN MATCHED THEN 
    UPDATE SET *
  WHEN NOT MATCHED 
    THEN INSERT * ;
  
select * from user_delta where id in (1 ,2, 99999)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC ## ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Enforce Data Quality with constraint
-- MAGIC
-- MAGIC Delta Lake support constraints. You can add any expression to force your table having a given field respecting this constraint. As example, let's make sure that the ID is never null.
-- MAGIC
-- MAGIC *Note: This is enforcing quality at the table level. Delta Live Tables offer much more advance quality rules and expectations in data Pipelines.*

-- COMMAND ----------

ALTER TABLE user_delta ADD CONSTRAINT id_not_null CHECK (id is not null);

-- COMMAND ----------

-- This command will fail as we insert a user with a null id::
INSERT INTO user_delta (id, creation_date, firstname, lastname, email, address, gender, age_group) 
                VALUES (null, now(), 'Quentin', 'Ambard', 'quentin.ambard@databricks.com', 'FR', '2', 3) 

-- COMMAND ----------

-- MAGIC %md ## ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Let's Travel back in Time!
-- MAGIC Databricks Delta’s time travel capabilities simplify building data pipelines for the following use cases. 
-- MAGIC
-- MAGIC * Audit Data Changes
-- MAGIC * Reproduce experiments & reports
-- MAGIC * Rollbacks
-- MAGIC
-- MAGIC As you write into a Delta table or directory, every operation is automatically versioned.
-- MAGIC
-- MAGIC You can query a table by:
-- MAGIC 1. Using a timestamp
-- MAGIC 1. Using a version number
-- MAGIC
-- MAGIC For more information, refer to [Introducing Delta Time Travel for Large Scale Data Lakes](https://databricks.com/blog/2019/02/04/introducing-delta-time-travel-for-large-scale-data-lakes.html)

-- COMMAND ----------

-- MAGIC %md ### ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Review Delta Lake Table History
-- MAGIC All the transactions for this table are stored within this table including the initial set of insertions, update, delete, merge, and inserts with schema modification

-- COMMAND ----------

DESCRIBE HISTORY user_delta

-- COMMAND ----------

-- MAGIC %md ### ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Time Travel via Version Number or Timestamp
-- MAGIC Below are SQL syntax examples of Delta Time Travel by using a Version Number

-- COMMAND ----------

-- Note that in our current version, user 99999 exists and we updated user 1 and 2
SELECT * FROM user_delta WHERE ID IN (1 ,2, 99999);

-- COMMAND ----------

-- We can request the table at version 2, before the upsert operation to get the original data:
SELECT * FROM user_delta VERSION AS OF 2 WHERE ID IN (1 ,2, 99999);

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC ### Restore a Previous Version
-- MAGIC You can restore a Delta table to its earlier state by using the `RESTORE` command, using a timestamp or delta version:
-- MAGIC
-- MAGIC ⚠️ Databricks Runtime 7.4 and above

-- COMMAND ----------

RESTORE TABLE user_delta TO VERSION AS OF 2;

SELECT * FROM user_delta WHERE ID IN (1 ,2, 99999);

-- COMMAND ----------

-- DBTITLE 1,Purging the history with VACUUM
-- We can easily delete all modification older than 200 hours:
VACUUM user_delta RETAIN 200 HOURS;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CLONE Delta Tables
-- MAGIC You can create a copy of an existing Delta table at a specific version using the `clone` command. This is very useful to get data from a PROD environment to a STAGING one, or archive a specific version for regulatory reason.
-- MAGIC
-- MAGIC There are two types of clones:
-- MAGIC * A **deep clone** is a clone that copies the source table data to the clone target in addition to the metadata of the existing table. 
-- MAGIC * A **shallow clone** is a clone that does not copy the data files to the clone target. The table metadata is equivalent to the source. These clones are cheaper to create.
-- MAGIC
-- MAGIC Any changes made to either deep or shallow clones affect only the clones themselves and not the source table.
-- MAGIC
-- MAGIC *Note: Shallow clone are pointers to the main table. Running a VACUUM may delete the underlying files and break the shallow clone!*

-- COMMAND ----------

-- DBTITLE 1,Shallow clone (zero copy)
CREATE TABLE IF NOT EXISTS user_delta_clone
  SHALLOW CLONE user_delta
  VERSION AS OF 2;

SELECT * FROM user_delta_clone;

-- COMMAND ----------

-- DBTITLE 1,Deep clone (copy data)
CREATE TABLE IF NOT EXISTS user_delta_clone_deep
  DEEP CLONE user_delta;

SELECT * FROM user_delta_clone_deep;

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC ### Generated columns
-- MAGIC
-- MAGIC Delta Lake makes it easy to add auto increment columns. This is done with the `GENERATED` keyword. Generated value can also be derivated from other fields.

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS user_delta_generated_id (
  id BIGINT GENERATED ALWAYS AS IDENTITY ( START WITH 10000 INCREMENT BY 1 ), 
  firstname STRING, 
  lastname STRING, 
  email STRING, 
  address STRING) ;

-- Note that we don't insert data for the id. The engine will handle that for us:
INSERT INTO user_delta_generated_id (firstname, lastname, email, address) SELECT
    firstname,
    lastname,
    email,
    address
  FROM user_delta;

-- The ID is automatically generated!
SELECT * from user_delta_generated_id;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC stop_all_streams()

-- COMMAND ----------

-- MAGIC %md ## ![](https://pages.databricks.com/rs/094-YMS-629/images/delta-lake-tiny-logo.png) Going further with Delta Lake
-- MAGIC
-- MAGIC ### Schema evolution 
-- MAGIC
-- MAGIC Delta Lake support schema evolution. You can add a new column and even more advanced operation such as [updating partition](https://docs.databricks.com/delta/delta-batch.html#change-column-type-or-name). For SQL MERGE operation you easily add new columns with `SET spark.databricks.delta.schema.autoMerge.enabled = true`
-- MAGIC
-- MAGIC More details from the [documentation](https://docs.databricks.com/spark/latest/spark-sql/language-manual/sql-ref-syntax-ddl-alter-table.html). 
-- MAGIC
-- MAGIC ### Identity columns, PK & FK 
-- MAGIC
-- MAGIC You can add auto-increment columns in your tables: `id BIGINT GENERATED ALWAYS AS IDENTITY ( START WITH 0 INCREMENT BY 1 )`, but also define Primary Keys and Foreign Keys.  
-- MAGIC
-- MAGIC For more details, check our demo `dbdemos.install('identity-pk-fk')` !
-- MAGIC
-- MAGIC ### Delta Sharing, open data sharing protocol
-- MAGIC
-- MAGIC [Delta Sharing](https://delta.io/sharing/) is an open standard to easily share your tables with external organization, using Databricks or any other system / cloud provider.
-- MAGIC
-- MAGIC For more details, check our demo `dbdemos.install('delta-sharing')` !

-- COMMAND ----------

-- MAGIC %md 
-- MAGIC
-- MAGIC Next: Discover how to boost your queries with [Delta Lake performance features]($./02-Delta-Lake-Performance) or go back to [00-Delta-Lake-Introduction]($./00-Delta-Lake-Introduction).
-- MAGIC
-- MAGIC