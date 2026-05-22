use product_catalog;

db.products.createIndex({ product_id: 1 }, { unique: true });
db.products.createIndex({ category: 1 });
db.products.createIndex({ brand: 1 });
db.products.createIndex({ product_name: "text", description: "text" });

db.products.updateMany(
  { category: "Mobile" },
  {
    $set: {
      color: "Black",
      storage: "128GB Storage",
      RAM: "6GB RAM",
      battery: "5000mAh",
      warranty: "1 Year Brand Warranty",
      processor: "Octa Core Processor"
    }
  }
);

db.products.updateMany(
  { category: "Laptop" },
  {
    $set: {
      color: "Silver",
      storage: "512GB SSD",
      RAM: "8GB RAM",
      battery: "Long Life Battery",
      warranty: "1 Year Onsite Warranty",
      processor: "Intel / AMD Processor"
    }
  }
);

db.products.updateMany(
  { category: "Wearables" },
  {
    $set: {
      color: "Black",
      storage: "Not Applicable",
      RAM: "Not Applicable",
      battery: "7 Days",
      warranty: "1 Year Warranty",
      processor: "Smart Sensor"
    }
  }
);

db.products.updateMany(
  { category: "Audio" },
  {
    $set: {
      color: "Black",
      storage: "Not Applicable",
      RAM: "Not Applicable",
      battery: "30 Hours Playback",
      processor: "Audio Chipset",
      warranty: "6 Months Warranty"
    }
  }
);

db.products.updateMany(
  { category: "Accessories" },
  {
    $set: {
      color: "White",
      storage: "Not Applicable",
      RAM: "Not Applicable",
      battery: "Not Applicable",
      processor: "Not Applicable",
      warranty: "6 Months Warranty"
    }
  }
);

db.products.updateMany(
  { category: "TV and Display" },
  {
    $set: {
      color: "Black",
      storage: "Smart TV Storage",
      RAM: "Not Available",
      battery: "Not Applicable",
      processor: "Display Processor",
      warranty: "1 Year Warranty"
    }
  }
);
