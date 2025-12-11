import { createRequire } from "module";
const require = createRequire(import.meta.url);
const palette = require("./palette.json");
export const variants = palette;
export default palette;
