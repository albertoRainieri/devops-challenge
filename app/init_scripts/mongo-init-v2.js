// Switch to the tech_challenge database
print("=== MongoDB Initialization Script Started ===");
print("Connecting to database: " + process.env.MONGO_INITDB_DATABASE);

db = db.getSiblingDB(process.env.MONGO_INITDB_DATABASE);
print("Switched to database: " + db.getName());

// Create collection with logging
print("Creating 'visits' collection...");
try {
  db.createCollection('visits');
  print("✓ 'visits' collection created successfully");
} catch (error) {
  if (error.code === 48) { // Collection already exists
    print("'visits' collection already exists, continuing...");
  } else {
    print("Error creating collection: " + error.message);
    throw error;
  }
}

// Check if collection is empty before inserting data
const documentCount = db.visits.countDocuments();
print("Current document count in 'visits' collection: " + documentCount);

if (documentCount === 0) {
  print("Collection is empty, inserting sample data...");
  
  const sampleData = [
    {
      visit_dt: new Date(),
      ip: '127.0.0.1',
      user_agent: 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)'
    },
    {
      visit_dt: new Date(),
      ip: '127.0.0.1',
      user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15.7; rv:143.0) Gecko/20100101 Firefox/143.0'
    },
    {
      visit_dt: new Date(),
      ip: '10.0.0.1',
      user_agent: 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:143.0) Gecko/20100101 Firefox/143.0'
    },
    {
      visit_dt: new Date(),
      ip: '192.168.1.52',
      user_agent: 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)'
    },
    {
      visit_dt: new Date(),
      ip: '10.0.1.5',
      user_agent: 'Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko'
    },
    {
      visit_dt: new Date(),
      ip: '10.0.0.150',
      user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
    }
  ];
  
  try {
    const result = db.visits.insertMany(sampleData);
    print("Successfully inserted " + result.insertedCount + " sample visit records");
    print("Inserted document IDs: " + JSON.stringify(result.insertedIds));
  } catch (error) {
    print("Error inserting sample data: " + error.message);
    throw error;
  }
} else {
  print("Collection already contains " + documentCount + " documents, skipping data insertion");
}

// Final verification
const finalCount = db.visits.countDocuments();
print("Final document count in 'visits' collection: " + finalCount);
print("=== MongoDB Initialization Script Completed ===");