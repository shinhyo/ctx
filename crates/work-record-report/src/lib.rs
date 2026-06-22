use serde::Serialize;
use work_record_core::{Evidence, WorkContext, WorkRecord, WorkRecordArchive};

#[derive(Debug, Clone, Serialize)]
pub struct ReportSummary {
    pub record_count: usize,
    pub evidence_count: usize,
    pub linked_pr_count: usize,
    pub tags: Vec<TagCount>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct TagCount {
    pub tag: String,
    pub count: usize,
}

pub fn summarize(records: &[WorkRecord], evidence: &[Evidence]) -> ReportSummary {
    let mut tag_counts = std::collections::BTreeMap::<String, usize>::new();
    for record in records {
        for tag in &record.tags {
            *tag_counts.entry(tag.clone()).or_default() += 1;
        }
    }

    ReportSummary {
        record_count: records.len(),
        evidence_count: evidence.len(),
        linked_pr_count: records
            .iter()
            .filter(|record| record.pr_url.is_some())
            .count(),
        tags: tag_counts
            .into_iter()
            .map(|(tag, count)| TagCount { tag, count })
            .collect(),
    }
}

pub fn render_text(records: &[WorkRecord], evidence: &[Evidence]) -> String {
    let summary = summarize(records, evidence);
    let mut out = String::new();
    out.push_str("Work Recorder Report\n");
    out.push_str(&format!("records: {}\n", summary.record_count));
    out.push_str(&format!("evidence: {}\n", summary.evidence_count));
    out.push_str(&format!("linked_prs: {}\n", summary.linked_pr_count));
    if !summary.tags.is_empty() {
        out.push_str("tags:\n");
        for tag in summary.tags {
            out.push_str(&format!("  {}: {}\n", tag.tag, tag.count));
        }
    }
    out
}

pub fn render_json(records: &[WorkRecord], evidence: &[Evidence]) -> serde_json::Result<String> {
    serde_json::to_string_pretty(&summarize(records, evidence))
}

pub fn context_markdown(context: &WorkContext) -> String {
    let mut out = String::new();
    out.push_str("# Work Context\n\n");
    if let Some(query) = &context.query {
        out.push_str(&format!("query: `{query}`\n\n"));
    }
    for record in &context.records {
        out.push_str(&format!("## {}\n", record.title));
        out.push_str(&format!("id: `{}`\n", record.id));
        if !record.tags.is_empty() {
            out.push_str(&format!("tags: {}\n", record.tags.join(", ")));
        }
        out.push('\n');
        out.push_str(&record.body);
        out.push_str("\n\n");
    }
    if !context.evidence.is_empty() {
        out.push_str("## Evidence\n");
        for evidence in &context.evidence {
            out.push_str(&format!(
                "- `{}` exited {} in {}ms\n",
                evidence.command, evidence.exit_code, evidence.duration_ms
            ));
        }
    }
    out
}

pub fn archive_json(archive: &WorkRecordArchive) -> serde_json::Result<String> {
    serde_json::to_string_pretty(archive)
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use uuid::Uuid;

    use super::*;

    #[test]
    fn summarizes_records() {
        let mut record = WorkRecord::new("One", "Body", vec!["cli".into()], "task", None);
        record.pr_url = Some("https://github.com/ctxrs/ctx/pull/1".into());
        let evidence = Evidence::new(
            Some(Uuid::new_v4()),
            "cargo test",
            0,
            String::new(),
            String::new(),
            Utc::now(),
            1,
        );

        let summary = summarize(&[record], &[evidence]);
        assert_eq!(summary.record_count, 1);
        assert_eq!(summary.linked_pr_count, 1);
        assert_eq!(
            summary.tags[0],
            TagCount {
                tag: "cli".into(),
                count: 1
            }
        );
    }
}
