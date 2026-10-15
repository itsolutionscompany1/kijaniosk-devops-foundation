module.exports.process = async (event) => {
  for (const record of event.Records) {
    console.log(`Processing receipt: ${record.s3.object.key}`);
    console.log(`Bucket: ${record.s3.bucket.name}`);
  }
  return { statusCode: 200, body: 'Receipts processed' };
};
