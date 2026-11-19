# robota.ua crosswalks

Code lists for the robota.ua vacancy sample (`Collector/data/exports/<timestamp>/vacancies.csv`).
Built on 5 Nov 2026 from export `20261105_072026` (242,220 vacancies) and from the API's
dictionary endpoints listed in its docs (`https://api.rabota.ua/swagger/docs/v1`).

## Used by `do/01_clean.do` (value labels)

| File | Codes for | Source |
|---|---|---|
| `robota_schedule.csv` | `schedule_id` | documented: `/dictionary/schedule` |
| `robota_branch.csv` | `branch_id` (employer industry) | documented: `/dictionary/branch` |
| `robota_city.csv` | `city_id`, plus oblast | documented: `/dictionary/city` |
| `robota_publication_type.csv` | `publication_type` | names from the API docs (enum), codes by order; code 4 confirmed in data |
| `robota_prof_level.csv` | `prof_level_id` | **no official list**: labels inferred from job titles (see `source` column) |

## Stored for later (not used in the Stata pipeline yet)

Kept for a later stage, e.g. as partial "ground truth" for LLM classification of
vacancies. Caveat: each dimension is filled for only part of the vacancies, and a
missing value means "not stated", not "no".

**Clusters** (`clusters_json`): dimensions such as employment type, experience, schedule,
education, each with one or more values. robota.ua has no dictionary endpoint for clusters;
names come inside each vacancy record (`ClusterDto` in the API docs), in Russian.

| File | Content |
|---|---|
| `robota_clusters_all.csv` | every dimension × value seen in the data: ids, API names, vacancy counts (2,084 rows) |
| `robota_clusters_selected.csv` | 47 values from 8 general dimensions, with proposed variable names and English labels (translations are mine) |

**Tags** (`tags_json`): search tags describing the job, mostly Russian. Each tag has a
`synonymGroupId` grouping near-duplicate spellings.

| File | Content |
|---|---|
| `robota_tags_all.csv` | 16,159 tags: id, API name, synonym group, number of vacancies, max `vacancySearchCount` seen |
| `robota_tag_groups.csv` | 4,739 synonym groups: most frequent tag name, number of tags and vacancies; `popular_tag_*` filled where the group id is in `/dictionary/popular-tags` |
| `robota_popular_tags.csv` | documented: `/dictionary/popular-tags` (41 entries; ids are synonym-group ids) |

Each tag id always has the same name and synonym group in the data. The top 500 synonym
groups cover 95% of vacancies.

**Languages** (`languages_json`, filled in about 2% of vacancies):

| File | Content |
|---|---|
| `robota_language.csv` | documented: `/dictionary/language` (`languageId`) |
| `robota_language_skill.csv` | documented: `/dictionary/language/skill` (`levelId`) |

The vacancy-level information is in the `tags_json`, `clusters_json` and
`languages_json` columns of the export (`vacancies.csv`); `01_clean.do` drops them before saving.
