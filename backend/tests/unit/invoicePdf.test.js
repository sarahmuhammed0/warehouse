// §28's document, rendered without a database.
//
// The layout is blocks now — a banner, a meta row, summary cards, a filled
// table, totals, notes — which means real geometry: page breaks mid-table,
// measured note boxes, a footer pinned to every page. Geometry is where this
// kind of code goes wrong, and it goes wrong on the inputs nobody renders by
// hand: no lines at all, a hundred lines, a note long enough to need its own
// page, a name wide enough to run into the next column.
//
// None of these assert on the PIXELS — pdfkit compresses its text stream, so
// the bytes are not searchable. What they assert is that a real PDF comes out,
// that it is the same every time, and that none of the arrangements above
// throws, which is what a broken page break actually does.

import { test } from "node:test";
import assert from "node:assert/strict";
import { Writable } from "node:stream";

import { writeInvoicePdf } from "../../src/modules/documents/invoicePdf.js";

/** Collects the stream so the finished bytes can be looked at. */
function render(args) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const sink = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk);
        callback();
      },
    });
    sink.on("finish", () => resolve(Buffer.concat(chunks)));
    sink.on("error", reject);
    try {
      writeInvoicePdf({ ...args, stream: sink });
    } catch (err) {
      reject(err);
    }
  });
}

const business = {
  name: "Karwan Furniture Factory",
  address: "Industrial Zone",
  city: "Erbil",
  country: "Iraq",
  phone: "+9647500000003",
  email: "hello@example.test",
  tax_number: "TX-991",
  currency: "IQD",
};

const template = {
  invoiceTitle: "INVOICE",
  currency: "IQD",
  dateFormat: "YYYY-MM-DD",
  headerText: "",
  footerText: "Thank you for your business.",
  paymentTerms: "Payable within 14 days of delivery.",
  returnPolicy: "Returns accepted within 7 days.",
  thankYouMessage: "Thank you.",
  signatureText: "Authorised by",
  fields: {
    itemSku: true,
    customerAddress: true,
    taxInfo: true,
    paymentTerms: true,
    returnPolicy: true,
    thankYou: true,
    signature: true,
  },
};

const order = {
  orderNumber: "INV-2026-000001",
  status: "completed",
  paymentStatus: "paid",
  orderDate: "2026-09-28 10:00:00",
  createdAt: "2026-09-28 10:00:00",
  customerName: "Ahmed Al-Rashid",
  customerPhone: "+9647500000010",
  subtotal: 150,
  discountAmount: 0,
  taxAmount: 0,
  extraCharges: 0,
  grandTotal: 150,
  paidAmount: 150,
  remainingAmount: 0,
};

const item = {
  productName: "Oak Dining Chair",
  sku: "CHR-OAK-1",
  quantity: 2,
  unitPrice: 75,
  taxAmount: 0,
  lineTotal: 150,
};

const isPdf = (bytes) => bytes.subarray(0, 5).toString("latin1") === "%PDF-";

test("it produces a real PDF", async () => {
  const bytes = await render({ business, template, order, items: [item] });

  assert.ok(isPdf(bytes), "the file has to start with the PDF header");
  assert.ok(bytes.includes(Buffer.from("%%EOF")), "and be closed off properly");
  assert.ok(bytes.length > 1000, `suspiciously small: ${bytes.length} bytes`);
});

test("two renders of the same order are identical, down to the byte", async () => {
  // Nothing in the DOCUMENT may be non-deterministic — no "generated at", no
  // run id. A reprint that differs from the original is not a reprint.
  //
  // Two fields are normalised away, and both describe the FILE rather than the
  // invoice: the trailer's /ID, which the PDF spec requires to be unique per
  // file, and CreationDate, which is when this copy was produced. Same
  // reasoning, and the same normalisation, as the §28 integration test.
  const strip = (buffer) =>
    buffer
      .toString("latin1")
      .replace(/\/ID \[<[0-9a-f]+> <[0-9a-f]+>\]/, "/ID [pinned]")
      .replace(/\(D:\d{14}Z?\)/g, "(D:pinned)");

  const first = await render({ business, template, order, items: [item] });
  const second = await render({ business, template, order, items: [item] });

  assert.equal(strip(first), strip(second));
});

test("a different order really does produce a different document", async () => {
  // The guard on the test above: normalising two fields away must not have
  // normalised away everything that distinguishes one invoice from another.
  const strip = (buffer) =>
    buffer
      .toString("latin1")
      .replace(/\/ID \[<[0-9a-f]+> <[0-9a-f]+>\]/, "/ID [pinned]")
      .replace(/\(D:\d{14}Z?\)/g, "(D:pinned)");

  const original = await render({ business, template, order, items: [item] });
  const changed = await render({
    business,
    template,
    order: { ...order, grandTotal: 999, orderNumber: "INV-2026-000002" },
    items: [item],
  });

  assert.notEqual(strip(original), strip(changed));
});

test("an order with no lines still renders", async () => {
  // The table draws its header and then nothing. Totals still follow it, and
  // the page must not collapse into the footer.
  const bytes = await render({ business, template, order, items: [] });
  assert.ok(isPdf(bytes));
});

test("a hundred lines break across pages without throwing", async () => {
  // The break is the fiddly part: a row must not be cut in half, and each new
  // page needs its own table header or the columns become unlabelled.
  const items = Array.from({ length: 100 }, (_, i) => ({ ...item, productName: `Item ${i + 1}` }));
  const bytes = await render({ business, template, order, items });

  assert.ok(isPdf(bytes));
  assert.ok(bytes.length > 5000, "a hundred lines is more than one page of content");
});

test("long text does not overflow its box or the page", async () => {
  const wordy = {
    ...template,
    paymentTerms: "Payable within fourteen days of delivery. ".repeat(12),
    returnPolicy: "Returns are accepted within seven days in original packaging. ".repeat(12),
    thankYouMessage: "Thank you for your continued business. ".repeat(12),
  };
  const bytes = await render({
    business,
    template: wordy,
    order: { ...order, customerName: "A customer with an extraordinarily long trading name".repeat(2) },
    items: [{ ...item, productName: "A product name far wider than the column that holds it".repeat(2) }],
  });

  assert.ok(isPdf(bytes));
});

test("the template's switches are honoured, and turning them all off still renders", async () => {
  const bare = {
    ...template,
    headerText: "",
    footerText: "",
    paymentTerms: "",
    returnPolicy: "",
    thankYouMessage: "",
    signatureText: "",
    fields: {
      itemSku: false,
      customerAddress: false,
      taxInfo: false,
      paymentTerms: false,
      returnPolicy: false,
      thankYou: false,
      signature: false,
    },
  };
  const bytes = await render({ business, template: bare, order, items: [item] });

  assert.ok(isPdf(bytes));
  // Fewer columns and no notes block: materially smaller than the full one.
  const full = await render({ business, template, order, items: [item] });
  assert.ok(bytes.length < full.length, "the switches have to actually remove things");
});

test("payments are listed when there are any, and their absence is not an error", async () => {
  const withPayments = await render({
    business,
    template,
    order,
    items: [item],
    payments: [
      { paidAt: "2026-09-28 10:05:00", method: "bank_transfer", amount: 100, reference: "TRF-1" },
      { paidAt: "2026-09-28 11:00:00", method: "cash", amount: 50, reference: null },
    ],
  });
  const without = await render({ business, template, order, items: [item] });

  assert.ok(isPdf(withPayments));
  assert.ok(withPayments.length > without.length, "two payment rows have to appear somewhere");
});

test("a business with almost nothing filled in still gets a document", async () => {
  // A brand-new tenant: a name and nothing else.
  const bytes = await render({
    business: { name: "New Co" },
    template: { ...template, currency: "", fields: { ...template.fields, taxInfo: true } },
    order: { ...order, customerName: null, customerPhone: null, paymentStatus: null },
    items: [item],
  });

  assert.ok(isPdf(bytes));
});
