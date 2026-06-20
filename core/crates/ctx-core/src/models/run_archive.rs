use serde::{Deserialize, Serialize};
use serde_json::Value;

mod normalize;

pub use normalize::*;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct RunArchiveNormalizationStats {
    pub redacted_absolute_paths: u32,
    pub redacted_secret_fields: u32,
    pub redacted_secret_values: u32,
    pub redacted_provider_refs: u32,
    pub redacted_pty_streams: u32,
    pub dropped_transient_events: u32,
    pub omitted_content_payloads: u32,
}

impl RunArchiveNormalizationStats {
    pub fn merge(&mut self, other: Self) {
        self.redacted_absolute_paths += other.redacted_absolute_paths;
        self.redacted_secret_fields += other.redacted_secret_fields;
        self.redacted_secret_values += other.redacted_secret_values;
        self.redacted_provider_refs += other.redacted_provider_refs;
        self.redacted_pty_streams += other.redacted_pty_streams;
        self.dropped_transient_events += other.dropped_transient_events;
        self.omitted_content_payloads += other.omitted_content_payloads;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NormalizedArchivePayload {
    pub value: Value,
    pub stats: RunArchiveNormalizationStats,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NormalizedArchiveText {
    pub text: String,
    pub stats: RunArchiveNormalizationStats,
}
