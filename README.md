# Readme.md
Accurate knowledge of a patient’s condition is critical. Electronic monitoring systems and health records provide rich information for performing predictive analytics. Here I am trying to  use ICU clinical data to predict the mortality of patients in one month after discharge.

About the Data:
The data provided in events.csv are event sequences. Each line of this file consists of a tuple with the format (patient id, event id, event description, timestamp, value).
patient id: Identifies the patients in order to differentiate them from others. For example, the patient in the example above has patient id 1053.
• event id: Encodes all the clinical events that a patient has had. For example, DRUG19122121 means that a drug with RxNorm code 19122121 was prescribed to the patient, DIAG319049 means the patient was diagnosed with a disease with SNOMED code 319049, and LAB3026361 means that a laboratory test with LOINC code 3026361 was performed on the patient.
• event description: Shows the text description of the event. For example, DIAG319049 is the code for Acute respiratory failure, and DRUG19122121 is the code for Insulin.
• timestamp: Indicates the date at which the event happened. Here the timestamp is not a real date but a shifted date to protect the privacy of patients.
• value: Contains the value associated to an event. See Table 1 for the detailed descrip- tion.

This is how we approach the problem.
A Logistic Regression classifier can be trained with historical health-care data to make future predictions. A training set D is composed of {(xi,yi)}N1 , where yi ∈ {0,1} is the label and xi ∈ Rd is the feature vector of the i-th patient. In logistic regression we have
p(y = 1|x ) = σ(wTx ), where w ∈ Rd is the learned coefficient vector and σ(t) = 1 iii 1+e−t
is the sigmoid function.
Suppose your system continuously collects patient data and predicts patient severity us-
ing Logistic Regression. When patient data vector x arrives to your system, the system needs to predict whether the patient has a severe condition (predicted label yˆ ∈ {0, 1}) and requires immediate care or not. The result of the prediction will be delivered to a physician, who can then take a look at the patient. Finally, the physician will provide feedback (truth label y ∈ {0, 1}) back to your system so that the system can be upgraded, i.e. w recomputed, to make better predictions in the future.

Descriptive Statistics 

Computing descriptive statistics on the data helps in developing predictive models. In this section, you need to write HIVE code that computes various metrics on the data. A skeleton code is provided as a starting point.
The definition of terms used in the result table are described below:
• Event Count : Number of events recorded for a given patient. Note that every line in the input file is an event.
• Encounter Count : Count of unique dates on which a given patient visited the ICU.
• Record Length : Duration (in number of days) between first event and last event for a given patient.

Transform data
we will convert the raw data to standardized format using Pig. Diagnostic, medication and laboratory codes for each patient should be used to construct the feature vector and the feature vector should be represented in SVMLight format. You will work with events.csv and mortality.csv files provided in data folder.
Listed below are a few concepts you need to know before beginning feature construction (for details please refer to lectures).
• Observation Window: The time interval containing events you will use to construct your feature vectors. Only events in this window should be considered. The observation window ends on the index date (defined below) and starts 2000 days (including 2000) prior to the index date.
• Prediction Window: A fixed time interval following the index date where we are observing the patient’s mortality outcome. This is to simulate predicting some length of time into the future. Events in this interval should not be included while constructing feature vectors. The size of prediction window is 30 days.
• Index date: The day on which we will predict the patient’s probability of dying during the subsequent prediction window. Events occurring on the index date should be considered within the observation window. Index date is determined as follows:
– For deceased patients: Index date is 30 days prior to the death date (timestamp field) in mortality.csv.
– For alive patients: Index date is the last event date in events.csv for each alive patient.

SGD Logistic Regression
