-- ***************************************************************************
-- TASK
-- Aggregate events into features of patient and generate training, testing data for mortality prediction.
-- Steps have been provided to guide you.
-- You can include as many intermediate steps as required to complete the calculations.
-- You can NOT touch the provided load path or variable names because it will be used in grading.
-- ***************************************************************************

-- ***************************************************************************
-- TESTS
-- To test, you can change the LOAD path for events and mortality to ../../test/events.csv and ../../test/mortality.csv, however, you MUST switch it back to original path in submission.
-- 6 tests have been provided to test all the subparts in this exercise.
-- Manually compare the output of each test against the csv's in test/expected folder.
-- ***************************************************************************

-- register a python UDF for converting data into SVMLight format
REGISTER utils.py USING jython AS utils;

-- load events file
events = LOAD '/bigdata-bootcamp/sample/hive/events/events.csv' USING PigStorage(',') AS (patientid:int, eventid:chararray, eventdesc:chararray, timestamp:chararray, value:float);

-- select required columns from events
events = FOREACH events GENERATE patientid, eventid, ToDate(timestamp, 'yyyy-MM-dd') AS etimestamp, value;

-- load mortality file
mortality = LOAD '/bigdata-bootcamp/sample/hive/mortality/mortality.csv' USING PigStorage(',') as (patientid:int, timestamp:chararray, label:int);

mortality = FOREACH mortality GENERATE patientid, ToDate(timestamp, 'yyyy-MM-dd') AS mtimestamp, label;

--To display the relation, use the dump command e.g. DUMP mortality;

-- ***************************************************************************
-- Compute the index dates for dead and alive patients
-- ***************************************************************************

-- perform join of events and mortality by patientid;

eventswithmort = JOIN events BY patientid LEFT OUTER, mortality BY patientid;


-- detect the events of dead patients and create it of the form (patientid, eventid, value, label, time_difference) where time_difference is the days between index date and each event timestamp
dead_filter = FILTER eventswithmort BY (mortality::label == 1);
deadevents = FOREACH dead_filter GENERATE events::patientid AS patientid,events::eventid AS eventid,events::value AS value,mortality::label AS label, DaysBetween(SubtractDuration(mortality::mtimestamp,'P30D'), events::etimestamp) AS time_difference;


aliveevents = -- detect the events of alive patients and create it of the form (patientid, eventid, value, label, time_difference) where time_difference is the days between index date and each event timestamp

--First do the join and then do the filter on alive patients
alive_ch = FOREACH eventswithmort GENERATE events::patientid AS patientid, events::eventid AS eventid, events::value AS value, events::etimestamp as etimestamp, (mortality::label IS NULL ? 0:1) AS label;

alive_filter = FILTER alive_ch BY (label == 0);

-- Group by on patient Id
alive_group = GROUP alive_filter BY (patientid);

-- Find the max date for each patient which will be used later to calculate difference in days
alive_index_date = FOREACH alive_group GENERATE group AS patientid, MAX(alive_filter.etimestamp) AS indexdate;

alive_index_join = JOIN alive_filter BY patientid, alive_index_date BY patientid;

-- create the final form of alive patients

aliveevents = FOREACH alive_index_join GENERATE alive_filter::patientid AS patientid, alive_filter::eventid AS eventid, alive_filter::value AS value, alive_filter::label AS label, DaysBetween(alive_index_date::indexdate,alive_filter::etimestamp) AS time_difference;


--TEST-1
deadevents = ORDER deadevents BY patientid, eventid;
aliveevents = ORDER aliveevents BY patientid, eventid;
STORE aliveevents INTO 'aliveevents' USING PigStorage(',');
STORE deadevents INTO 'deadevents' USING PigStorage(',');

-- ***************************************************************************
-- Filter events within the observation window and remove events with missing values
-- Tip: please ensure the number of rows of your output feature is 3618, otherwise the following sections will be highly impacted and make you lose all the relevant credits.
-- ***************************************************************************

filtered = -- contains only events for all patients within the observation window of 2000 days and is of the form (patientid, eventid, value, label, time_difference)

total = UNION aliveevents, deadevents;
discard = FILTER total BY value IS NOT NULL;
filtered = FILTER discard BY (time_difference<=2000L) AND (time_difference>=0L);
--STORE filtered INTO 'test_filtered' USING PigStorage(',');



--TEST-2
filteredgrpd = GROUP filtered BY 1;
filtered = FOREACH filteredgrpd GENERATE FLATTEN(filtered);
filtered = ORDER filtered BY patientid, eventid,time_difference;
STORE filtered INTO 'filtered' USING PigStorage(',');

-- ***************************************************************************
-- Aggregate events to create features
-- ***************************************************************************
filtered_group = GROUP filtered BY (patientid,eventid);
featureswithid = FOREACH filtered_group GENERATE group.$0 AS patientid,group.$1 AS eventid,COUNT(filtered.value) AS featurevalue;

 -- for group of (patientid, eventid), count the number of  events occurred for the patient and create relation of the form (patientid, eventid, featurevalue)



--TEST-3
featureswithid = ORDER featureswithid BY patientid, eventid;
STORE featureswithid INTO 'features_aggregate' USING PigStorage(',');

-- ***************************************************************************
-- Generate feature mapping
-- ***************************************************************************
event_names = FOREACH featureswithid GENERATE eventid;
event_names = DISTINCT event_names;
event_names = ORDER event_names BY eventid;
event_names_index = RANK event_names;
all_features = FOREACH event_names_index GENERATE ($0-1) AS idx, $1;

-- compute the set of distinct eventids obtained from previous step, sort them by eventid and then rank these features by eventid to create (idx, eventid). Rank should start from 0.

-- store the features as an output file
STORE all_features INTO 'features' using PigStorage(' ');

join_feature = JOIN featureswithid BY eventid, all_features BY eventid;
features = FOREACH join_feature GENERATE featureswithid::patientid AS patientid, all_features::idx AS idx, featureswithid::featurevalue AS featurevalue;

-- perform join of featureswithid and all_features by eventid and replace eventid with idx. It is of the form (patientid, idx, featurevalue)




--TEST-4
features = ORDER features BY patientid, idx;
STORE features INTO 'features_map' USING PigStorage(',');

-- ***************************************************************************
-- Normalize the values using min-max normalization
-- Use DOUBLE precision
-- ***************************************************************************
id_grouped = GROUP features BY idx;
maxvalues = FOREACH id_grouped GENERATE group AS idx, MAX(features.featurevalue) AS maxvalue;

-- group events by idx and compute the maximum feature value in each group. I t is of the form (idx, maxvalue)

normalized = JOIN features BY idx, maxvalues BY idx;

-- join features and maxvalues by idx

features = FOREACH normalized GENERATE features::patientid AS patientid, features::idx AS idx, (1.0*(double)features::featurevalue/(double)maxvalues::maxvalue) AS normalizedfeaturevalue;
-- compute the final set of normalized features of the form (patientid, idx, normalizedfeaturevalue)


--TEST-5
features = ORDER features BY patientid, idx;
STORE features INTO 'features_normalized' USING PigStorage(',');

-- ***************************************************************************
-- Generate features in svmlight format
-- features is of the form (patientid, idx, normalizedfeaturevalue) and is the output of the previous step
-- e.g.  1,1,1.0
--  	 1,3,0.8
--	     2,1,0.5
--       3,3,1.0
-- ***************************************************************************

grpd = GROUP features BY patientid;
grpd_order = ORDER grpd BY $0;
features = FOREACH grpd_order
{
    sorted = ORDER features BY idx;
    generate group as patientid, utils.bag_to_svmlight(sorted) as sparsefeature;
}

-- ***************************************************************************
-- Split into train and test set
-- labels is of the form (patientid, label) and contains all patientids followed by label of 1 for dead and 0 for alive
-- e.g. 1,1
--	2,0
--      3,1
-- ***************************************************************************
labels = FOREACH filtered GENERATE patientid,label;
labels = DISTINCT labels;
-- create it of the form (patientid, label) for dead and alive patients

--Generate sparsefeature vector relation
samples = JOIN features BY patientid, labels BY patientid;
samples = DISTINCT samples PARALLEL 1;
samples = ORDER samples BY $0;
samples = FOREACH samples GENERATE $3 AS label, $1 AS sparsefeature;


--TEST-6
STORE samples INTO 'samples' USING PigStorage(' ');

-- randomly split data for training and testing
DEFINE rand_gen RANDOM('6505');
samples = FOREACH samples GENERATE rand_gen() as assignmentkey, *;
SPLIT samples INTO testing IF assignmentkey <= 0.20, training OTHERWISE;
training = FOREACH training GENERATE $1..;
testing = FOREACH testing GENERATE $1..;

-- save training and tesing data
STORE testing INTO 'testing' USING PigStorage(' ');
STORE training INTO 'training' USING PigStorage(' ');
