-- ==============================================================================
-- Customer Data Platform (CDP) for NotNaked
-- Universal Data Model (UDM) Compliant MySQL Database Schema
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Party
-- Represents any individual or organization. For our CDP, it primarily represents 
-- customers (Persons) but is abstracted to support B2B (Organizations) if needed.
-- ------------------------------------------------------------------------------
CREATE TABLE Party (
    party_id VARCHAR(40) NOT NULL,
    party_type_enum_id VARCHAR(40) NOT NULL COMMENT 'e.g., PERSON or ORGANIZATION',
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_modified_date DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (party_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 2. Person
-- Stores specific basic information for individual customers. 
-- Subtype of Party.
-- ------------------------------------------------------------------------------
CREATE TABLE Person (
    party_id VARCHAR(40) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender_enum_id VARCHAR(40),
    PRIMARY KEY (party_id),
    CONSTRAINT fk_person_party FOREIGN KEY (party_id) REFERENCES Party(party_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 3. ContactMech (Contact Mechanism)
-- Base table for any contact method (Email, Phone, Web URL/Social Handle, Postal).
-- ------------------------------------------------------------------------------
CREATE TABLE ContactMech (
    contact_mech_id VARCHAR(40) NOT NULL,
    contact_mech_type_enum_id VARCHAR(40) NOT NULL COMMENT 'e.g., EMAIL_ADDRESS, TELECOM_NUMBER, POSTAL_ADDRESS, SOCIAL_MEDIA',
    info_string VARCHAR(255) COMMENT 'Used for Emails, URLs, or Social Handles',
    created_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_modified_date DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (contact_mech_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 4. PostalAddress
-- Stores detailed address information. Subtype of ContactMech.
-- ------------------------------------------------------------------------------
CREATE TABLE PostalAddress (
    contact_mech_id VARCHAR(40) NOT NULL,
    address1 VARCHAR(255) NOT NULL,
    address2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    province_geo_id VARCHAR(40) COMMENT 'State/Province',
    postal_code VARCHAR(40) NOT NULL,
    country_geo_id VARCHAR(40) NOT NULL,
    PRIMARY KEY (contact_mech_id),
    CONSTRAINT fk_postal_contactmech FOREIGN KEY (contact_mech_id) REFERENCES ContactMech(contact_mech_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 5. TelecomNumber
-- Stores telephone number details. Subtype of ContactMech.
-- ------------------------------------------------------------------------------
CREATE TABLE TelecomNumber (
    contact_mech_id VARCHAR(40) NOT NULL,
    country_code VARCHAR(10),
    area_code VARCHAR(10),
    contact_number VARCHAR(40) NOT NULL,
    PRIMARY KEY (contact_mech_id),
    CONSTRAINT fk_telecom_contactmech FOREIGN KEY (contact_mech_id) REFERENCES ContactMech(contact_mech_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 6. PartyContactMech
-- Associates a Party with a Contact Mechanism. This resolves many-to-many 
-- relationships and supports multiple addresses, emails, phones, etc., per customer.
-- Tracks purposes (Shipping, Billing, Primary Phone) and marketing opt-ins.
-- ------------------------------------------------------------------------------
CREATE TABLE PartyContactMech (
    party_id VARCHAR(40) NOT NULL,
    contact_mech_id VARCHAR(40) NOT NULL,
    contact_mech_purpose_enum_id VARCHAR(40) NOT NULL COMMENT 'e.g., SHIPPING_LOCATION, BILLING_LOCATION, PRIMARY_EMAIL',
    from_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    thru_date DATETIME,
    opt_in_ind CHAR(1) DEFAULT 'N' COMMENT 'Y or N for marketing communication opt-in preference',
    verified_ind CHAR(1) DEFAULT 'N' COMMENT 'Y or N indicating if the contact method is verified',
    PRIMARY KEY (party_id, contact_mech_id, contact_mech_purpose_enum_id, from_date),
    CONSTRAINT fk_pcm_party FOREIGN KEY (party_id) REFERENCES Party(party_id) ON DELETE CASCADE,
    CONSTRAINT fk_pcm_contactmech FOREIGN KEY (contact_mech_id) REFERENCES ContactMech(contact_mech_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 7. PartyIdentification
-- Stores alternate IDs (like Shopify Customer ID, Loyalty IDs) for the customer.
-- Ensures seamless integration with external systems.
-- ------------------------------------------------------------------------------
CREATE TABLE PartyIdentification (
    party_id VARCHAR(40) NOT NULL,
    party_id_type_enum_id VARCHAR(40) NOT NULL COMMENT 'e.g., SHOPIFY_CUST_ID',
    id_value VARCHAR(255) NOT NULL,
    PRIMARY KEY (party_id, party_id_type_enum_id),
    CONSTRAINT fk_partyid_party FOREIGN KEY (party_id) REFERENCES Party(party_id) ON DELETE CASCADE,
    UNIQUE KEY unique_id_value (party_id_type_enum_id, id_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------------------------
-- 8. CustomerPreference
-- Key-Value table for flexible tracking of other marketing or communication 
-- preferences (e.g., Prefers SMS over Email).
-- ------------------------------------------------------------------------------
CREATE TABLE CustomerPreference (
    party_id VARCHAR(40) NOT NULL,
    preference_key VARCHAR(100) NOT NULL COMMENT 'e.g., PREFERRED_COMM_CHANNEL',
    preference_value VARCHAR(255) NOT NULL COMMENT 'e.g., EMAIL',
    PRIMARY KEY (party_id, preference_key),
    CONSTRAINT fk_custpref_party FOREIGN KEY (party_id) REFERENCES Party(party_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
