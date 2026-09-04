-- Legal acceptance audit trail (db_version 76 -> 77).
--
-- One row per (account, document, version, context) acceptance event. Document
-- CONTENT and the CURRENT version/effective-date for each of the three legal
-- documents (terms_of_service, purchase_terms, privacy_policy) live in code,
-- not in this table -- see plugins/backpackot-legal/src/LegalDocuments.php.
-- That keeps "edit the text, bump the version, deploy" a plain code change
-- with no admin CMS to build, matching how the rest of this project manages
-- content. This table only answers "who accepted what, when, and how" --
-- the thing that genuinely has to be durable, queryable, per-account state.
--
-- Bumping the version string in LegalDocuments.php is what forces
-- re-acceptance (an account's newest row for that document_type is compared
-- against the current version). Editing the document text WITHOUT bumping
-- the version -- a typo fix -- does not require anyone to re-accept.
--
-- `immediate_delivery_ack` and `order_reference` only apply to
-- purchase_terms acceptances (the checkout's second, separate checkbox and
-- the PayPal transaction it ends up tied to); they stay NULL/0 for
-- terms_of_service acceptances. Not worth a second table for two columns
-- that are simply unused on the other document types.

function onUpdateDatabase()
	logMigration("Updating database to version 77 (legal acceptance audit trail)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `legal_acceptances` (
			`id` int NOT NULL AUTO_INCREMENT,
			`account_id` int NOT NULL,
			`document_type` varchar(32) NOT NULL,
			`version` varchar(16) NOT NULL,
			`accepted_at` int unsigned NOT NULL,
			`context` varchar(32) NOT NULL,
			`immediate_delivery_ack` tinyint(1) NOT NULL DEFAULT '0',
			`order_reference` varchar(64) DEFAULT NULL,
			`ip_address` varchar(45) DEFAULT NULL,
			`user_agent` varchar(255) DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `by_account_type` (`account_id`, `document_type`),
			KEY `by_order` (`order_reference`),
			FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create legal_acceptances")
		return false
	end

	logMigration("legal_acceptances created")
	return true
end
