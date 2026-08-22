// Vercel function entry — vercel.json rewrites every path here.
// Plain JS on purpose: the app itself is compiled by tsc (npm run build),
// which emits the decorator metadata Nest's DI needs.
const { getApp } = require('../dist/serverless');

module.exports = async (req, res) => {
  const app = await getApp();
  app(req, res);
};
