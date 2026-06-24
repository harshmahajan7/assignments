# SystemMessage — Complete Hinglish Explanation 🚀

> **Codebase**: Maarg (Moqui Framework) — `maarg/framework/entity/ServiceEntities.xml`
> **Package**: `moqui.service.message`

---

## 🌐 Big Picture — Pehle samjho kya hota hai

Socho ek courier system hai. Ek system se doosre system ko **data packets** bhejne hote hain — jaise Shopify se OMS ko orders, ya OMS se Shopify ko fulfillment status. Yahi kaam `SystemMessage` karta hai.

**SystemMessage = ek "courier parcel" hai jo do systems ke beech travel karta hai.**

Har message ka ek:
- **Type** hota hai (kya cheez bheji ja rahi hai — e.g. "Order Feed")
- **Remote** hota hai (kahan se / kahan ko — e.g. "Shopify Store ABC")
- **Status** hota hai (parcel ka track — e.g. "Produced", "Sent", "Consumed")
- **Error log** hota hai agar parcel fail ho jaaye

---

## 📦 Entity 1: `SystemMessage` — The Core "Message" Record

**File**: `maarg/framework/entity/ServiceEntities.xml` (Line 178)

Yeh **main entity** hai. Har ek message (incoming ya outgoing) ka ek row yahan store hota hai.

### Fields ki Table:

| Field | Type | Role (Hinglish mein) |
|-------|------|----------------------|
| `systemMessageId` | id (PK) | Message ka unique ID — har message ka apna ek number |
| `systemMessageTypeId` | id (FK) | Kaunsa type ka message hai — e.g. "FulfillmentFeed", "OrderImport" |
| `systemMessageRemoteId` | id (FK) | Kis remote system se aaya / kahan bhejna hai — e.g. "Shopify Store ID" |
| `statusId` | id | Message ka status — Produced? Sent? Consumed? Error? |
| `isOutgoing` | Y/N | **Y = Bahar bhej raha hai** (OMS → Shopify), **N = Andar aa raha hai** (Shopify → OMS) |
| `initDate` | date-time | Incoming ke liye: kab receive hua. Outgoing ke liye: kab produce hua |
| `processedDate` | date-time | Incoming ke liye: kab consume (process) hua. Outgoing: kab actually send hua |
| `lastAttemptDate` | date-time | Aakhri baar kab try kiya gaya send/consume karne ki |
| `failCount` | integer | Kitni baar fail hua — retry limit ke liye use hota hai |
| `parentMessageId` | id (FK) | Agar ek bada message chhote pieces mein split hua, toh original message ka ID |
| `ackMessageId` | id (FK) | Acknowledgement message ka ID — confirmation ke liye |
| `remoteMessageId` | text-medium | Remote system (e.g. Shopify) ka apna ID, jaise Shopify Fulfillment ID |
| `messageText` | text-very-long | **Asli data** — JSON, file path, XML content jo bheja/aaya hai |
| `senderId` | text-short | Bhejne wale ka ID (EDI/OAGIS standard ke liye) |
| `receiverId` | text-short | Receive karne wale ka ID |
| `messageId` | text-short | Message ka envelope-level unique ID (globally ya sender ke context mein) |
| `messageDate` | date-time | Message ke andar ki date (envelope mein likh ke aata hai) |
| `docType` | text-short | Document ka type — OAGIS Noun / EDI functional ID |
| `docSubType` | text-short | Document ka sub-type — OAGIS Verb / EDI transaction set |
| `docControl` | text-short | Control number (EDI GS06) |
| `docSubControl` | text-short | Sub control number (EDI ST02) |
| `docVersion` | text-short | Document version (OAGIS revision / X12 version) |
| `triggerVisitId` | id (FK) | Kaun user tha jab message trigger hua — audit ke liye |

### 🛒 Extended fields (Shopify Connector ne add kiye — `ShopifyEntities.xml`):

| Field | Type | Role |
|-------|------|------|
| `orderId` | id | Order ka reference — search easy karne ke liye |
| `consumeSmrId` | id | Jab consume karte time ek alag Remote ID chahiye hoti hai, woh yahan store hoti hai |

---

### Status Lifecycle — Message ka Safar 🗺️

```
OUTGOING (Bahar bheja jaata hai):
  SmsgProduced → SmsgSending → SmsgSent → SmsgConfirmed
                                        → SmsgRejected
  (Koi bhi stage se) → SmsgError → (retry se wapas kisi stage par)
  (Koi bhi stage se) → SmsgCancelled

INCOMING (Andar aata hai):
  SmsgReceived → SmsgConsuming → SmsgConsumed → SmsgConfirmed
                                               → SmsgRejected
  (Koi bhi stage se) → SmsgError → (retry)
  (Koi bhi stage se) → SmsgCancelled
```

**Practical Example (Shopify Fulfillment):**
1. OMS mein ek order ship ho gaya → **SmsgProduced** (message bana)
2. Shopify ko bhejne ki koshish → **SmsgSending**
3. Shopify ne accept kar liya → **SmsgSent**
4. Shopify ne confirm kiya → **SmsgConfirmed** ✅

---

## 🏷️ Entity 2: `SystemMessageType` — Message ka Blueprint

**File**: `maarg/framework/entity/ServiceEntities.xml` (Line 409)

Yeh entity batati hai ki **ek particular type ke message ko kaisa handle karna hai**. Jaise courier mein "Express Delivery" aur "Standard Delivery" ke alag rules hote hain.

### Fields:

| Field | Type | Role |
|-------|------|------|
| `systemMessageTypeId` | id (PK) | Type ka unique ID — e.g. `"FulfillmentFeed"`, `"CreateShopifyFulfillment"` |
| `description` | text-medium | Human-readable naam |
| `produceServiceName` | text-medium | Kaunsa service call karo message **banane** ke liye (documentation purpose) |
| `consumeServiceName` | text-medium | Kaunsa service call karo message **process** karne ke liye (received message ko digest karna) |
| `produceAckServiceName` | text-medium | Acknowledgement message produce karne ka service |
| `produceAckOnConsumed` | Y/N | Automatically ACK bhejna hai jab message consume ho? |
| `sendServiceName` | text-medium | Kaunsa service call karo message **bhejne** ke liye (actual HTTP/SFTP call) |
| `receiveServiceName` | text-medium | Kaunsa service call karo message **receive** karne ke liye |
| `contentType` | text-short | Message ka content type (e.g. `application/json`) |
| `receivePath` | text-medium | Remote server par file kahan dhundo (SFTP path pattern) |
| `receiveFilePattern` | text-medium | Regex — kaun se file names match karni hain |
| `receiveResponseEnumId` | id | File receive karne ke baad kya karo: **None** / **Delete** / **Move** |
| `receiveMovePath` | text-medium | Agar "Move" karna hai, toh kahan move karo |
| `sendPath` | text-medium | Remote server par file kahan daalo (outgoing ke liye path/pattern) |

### 🔧 Extended fields (Shopify Connector):

| Field | Type | Role |
|-------|------|------|
| `parentTypeId` | id | Parent type ka reference — types ko hierarchy mein organize karna |

**Real Example:**
- Type = `FulfillmentFeed`
  - `consumeServiceName` = `co.hotwax.shopify.system.ShopifySystemMessageServices.consume#FulfillmentFeed`
  - `sendServiceName` = `co.hotwax.shopify.system.ShopifySystemMessageServices.send#ShopifyFulfillmentSystemMessage`

---

## 🌍 Entity 3: `SystemMessageRemote` — Remote System ka Config

**File**: `maarg/framework/entity/ServiceEntities.xml` (Line 472)

Yeh entity ek **remote system ka "address book entry"** hai. Har Shopify store, ya koi bhi bahari system, ek `SystemMessageRemote` record ke through represent hota hai.

Yeh basically batata hai:
- Remote system **kahan** hai (URL)
- **Kaisa authenticate** karo usse
- **Kaun sa user** use karo

### Fields (Grouped):

#### 🔗 Connection Fields:
| Field | Role |
|-------|------|
| `systemMessageRemoteId` | Unique ID — e.g. `"SHOPIFY_STORE_1"` |
| `description` | Human-readable naam |
| `sendUrl` | Outgoing messages ke liye URL — e.g. Shopify API endpoint |
| `receiveUrl` | Incoming messages ke liye URL — external system se receive karne ka URL |
| `remoteCharset` | Character encoding — e.g. `UTF-8` |
| `remoteAttributes` | SFTP servers ke liye: file attributes set karna support karta hai ya nahi (`N` = nahi) |
| `sendServiceName` | `SystemMessageType.sendServiceName` ko override kar sakta hai |

#### 🔐 Authentication Fields:
| Field | Role |
|-------|------|
| `username` | Basic auth ke liye username |
| `password` | Basic auth password (encrypted store hota hai DB mein) |
| `publicKey` | RSA public key (key-based auth ke liye) |
| `privateKey` | RSA private key — **encrypted** store hoti hai |
| `remotePublicKey` | Remote system ka public key — decryption/signature validation ke liye |
| `sharedSecret` | HMAC signing ke liye shared secret — **encrypted** |
| `sendSharedSecret` | Alag send secret (agar receive aur send ke different secrets ho) |
| `authHeaderName` | Auth header ka naam — e.g. `"X-Shopify-Access-Token"` |
| `messageAuthEnumId` | Auth method jo use hoti hai receive karte time |
| `sendAuthEnumId` | Auth method jo use hoti hai send karte time |

**Auth Types (Enum):**
- `SmatNone` — Koi auth nahi
- `SmatLogin` — Username/password (API key, basic auth)
- `SmatHmacSha256` — HMAC SHA-256 signature
- `SmatHmacSha256Timestamp` — HMAC SHA-256 + timestamp (Shopify webhooks yahi use karte hain)

#### 📋 Identity / EDI Fields:
| Field | Role |
|-------|------|
| `systemMessageTypeId` | Optional — agar yeh remote sirf ek type ke messages ke liye hai |
| `internalId` | Hamara apna system ID (EDI ISA06/08) |
| `internalIdType` | ID type |
| `internalAppCode` | Application code (EDI GS02/03) |
| `remoteId` | Remote system ka ID |
| `remoteIdType` | Remote ID type |
| `remoteAppCode` | Remote application code |
| `ackRequested` | ACK chahiye? (EDI standard specific values) |
| `usageCode` | Production vs Test mode |

#### 📄 EDI Formatting Fields:
| Field | Role |
|-------|------|
| `segmentTerminator` | EDI segment end character |
| `elementSeparator` | EDI element separator |
| `componentDelimiter` | EDI component delimiter |
| `escapeCharacter` | Escape character |

#### 🔑 Special Field:
| Field | Role |
|-------|------|
| `preAuthMessageRemoteId` | Agar SSO/pre-auth ke liye alag remote system hai (e.g. OAuth server) |

### 🛒 Extended fields (Shopify Connector):
| Field | Role |
|-------|------|
| `accessScopeEnumId` | Shopify shop ka access scope (e.g. read_orders, write_fulfillments) |
| `oldSharedSecret` | Purana shared secret — key rotation ke time kaam aata hai |

---

## ❌ Entity 4: `SystemMessageError` — Error Log

**File**: `maarg/framework/entity/ServiceEntities.xml` (Line 604)

Yeh entity ek **error diary** hai. Jab bhi koi message fail hota hai, uska reason yahan record hota hai.

### Fields:

| Field | Type | Role |
|-------|------|------|
| `systemMessageId` | id (PK, FK) | Kis message ka error hai — SystemMessage se linked |
| `errorDate` | date-time (PK) | Kab error aaya — same message ke multiple errors alag timestamps se distinguish hote hain |
| `attemptedStatusId` | id | Kaun se status mein jaate waqt error aaya — e.g. `SmsgConsuming` par fail hua |
| `errorText` | text-very-long | Actual error message / stack trace / description |

> **Note**: `errorTypeId` ek **commented-out future field** tha (`reasonCode`). Current implementation mein sirf `attemptedStatusId` aur `errorText` se kaam chalaya jaata hai.

**Practical Example:**
```
systemMessageId = "10001"
errorDate = "2026-05-16 10:30:00"
attemptedStatusId = "SmsgConsuming"
errorText = "Shopify API returned 422: Fulfillment already exists"
```

---

## 🔧 Entity 5: `SystemMessageTypeParameter` — Extra Configuration

**File**: `maarg/runtime/component/mantle-shopify-connector/entity/ShopifyEntities.xml` (Line 21)

Yeh entity ek **configuration parameter store** hai — jab `SystemMessageType` ke ek fixed field mein cheez define karna possible na ho, toh extra key-value pairs yahan store karte hain.

### Fields:

| Field | Type | Role |
|-------|------|------|
| `systemMessageTypeId` | id (PK) | Kis type ka parameter hai |
| `parameterName` | id (PK) | Parameter ka naam — e.g. `"consumeSmrId"`, `"fromDateBuffer"` |
| `parameterValue` | text-long | Parameter ki value |
| `systemMessageRemoteId` | id | Optional — agar parameter specific remote ke liye different ho |

**Common Parameters jo use hote hain:**
- `consumeSmrId` — Jab consume karte time ek alag Remote ID chahiye
- `fromDateBuffer` — Date filter ke liye buffer minutes
- `namespaces` — Shopify metafield namespaces (comma-separated)

---

## 🗺️ Entity 6: `SystemMessageAndType` — View (Read-only Join)

**File**: `ShopifyEntities.xml` (Line 56)

Yeh ek **view entity** hai — actual table nahi hai, sirf ek query shortcut hai.

```
SystemMessage + SystemMessageType ko join karke ek view banaya hai
```

Isse directly query kar sakte ho aur ek saath message aur type dono ke fields milte hain.

---

## 🔄 Entity 7: `SystemMessageEnumMap` — Value Mapping

**File**: `maarg/framework/entity/ServiceEntities.xml` (Line 593)

Jab internal system mein ek Enum value hoti hai (e.g. `ORDER_PLACED`) aur remote system (e.g. Shopify) mein usse alag naam se jaana jaata hai (e.g. `"placed"`), toh yeh mapping yahan store hoti hai.

| Field | Role |
|-------|------|
| `systemMessageRemoteId` | Kis remote ke liye mapping |
| `enumId` | Hamara internal Enum ID |
| `mappedValue` | Remote system ka corresponding value |

---

## 🔁 Service Flow — Message ka Poora Life Cycle

```
                    ┌─────────────────────────────────────────────┐
                    │           OUTGOING MESSAGE                  │
                    │                                             │
  Business Logic    │  queue#SystemMessage                        │
  (e.g. order       │  ────────────────→  [SmsgProduced]          │
  shipped)          │                          ↓                  │
                    │              send#ProducedSystemMessage      │
                    │                     ↓                       │
                    │           SystemMessageType.sendServiceName  │
                    │           (HTTP call to Shopify API)         │
                    │                     ↓                       │
                    │                [SmsgSent]                   │
                    └─────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────┐
                    │           INCOMING MESSAGE                  │
                    │                                             │
  Shopify Webhook   │  receive#IncomingSystemMessage              │
  / SFTP Poll       │  ────────────────→  [SmsgReceived]          │
                    │                          ↓                  │
                    │             consume#ReceivedSystemMessage   │
                    │                     ↓                       │
                    │         SystemMessageType.consumeServiceName │
                    │         (Business logic — create order etc) │
                    │                     ↓                       │
                    │                [SmsgConsumed]               │
                    └─────────────────────────────────────────────┘
```

---

## 🏗️ Entity Relationships — Visual Map

```
SystemMessageType (Blueprint)
    │
    ├──→ SystemMessageTypeParameter (Extra config)
    │
    └──→ SystemMessage (Actual message record)
              │
              ├──→ SystemMessageRemote (Kaun sa remote system)
              │         └──→ SystemMessageEnumMap (Value mappings)
              │
              ├──→ SystemMessageError (Error logs)
              │
              ├──→ SystemMessage (Parent — if split)
              └──→ SystemMessage (Ack message)
```

---

## 🛒 Real-World Shopify Example

**Scenario**: OMS se Shopify ko fulfillment bhejni hai

1. **SystemMessageRemote** record: `SHOPIFY_PROD_STORE`
   - `sendUrl` = `https://mystore.myshopify.com/admin/api/2024-01/graphql.json`
   - `username` = `shpat_xxxxx` (Access Token)
   - `messageAuthEnumId` = `SmatLogin`

2. **SystemMessageType** record: `CreateShopifyFulfillment`
   - `sendServiceName` = `co.hotwax.shopify.system.ShopifySystemMessageServices.send#ShopifyFulfillmentSystemMessage`

3. **SystemMessage** record created:
   - `systemMessageTypeId` = `CreateShopifyFulfillment`
   - `systemMessageRemoteId` = `SHOPIFY_PROD_STORE`
   - `isOutgoing` = `Y`
   - `statusId` = `SmsgProduced`
   - `messageText` = `{"shopifyOrderId": "123", "trackingNumber": "TRK001", ...}`

4. Jab send service call hoti hai:
   - API call Shopify ko → success
   - `statusId` → `SmsgSent`
   - `remoteMessageId` → Shopify ka Fulfillment ID

5. Agar fail ho: `SystemMessageError` create hota hai:
   - `attemptedStatusId` = `SmsgSending`
   - `errorText` = `"Shopify API Error: 422 Unprocessable"`

---

## 📌 Quick Summary Table

| Entity | Kya hai | Kitne records |
|--------|---------|---------------|
| `SystemMessage` | Har ek message ka record | Bahut saare (transactional) |
| `SystemMessageType` | Message type ka blueprint | Kam (configuration) |
| `SystemMessageRemote` | Remote system config | Kam (configuration) |
| `SystemMessageError` | Error log | Message ke fail hone par |
| `SystemMessageTypeParameter` | Extra config params | Type ke hisaab se |
| `SystemMessageAndType` | View (join) | Actual table nahi |
| `SystemMessageEnumMap` | Value mapping | Integration specific |
