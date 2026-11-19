"""
00_text_features.py  --  features of each vacancy from its text and robota.ua tags

Input : <export>/vacancies_with_text.parquet   (argument 1: the export folder)
        data/crosswalks/occupation_groups.csv, occupation_rules.csv  (title -> ISCO-08,
        built for the KSE work.ua titles) and occupation_rules_robota.csv (additions
        for robota.ua titles)
Output: Project/data/temp/robota_text_features.csv         one row per vacancy id
        Project/data/temp/robota_text_features_labels.csv  value labels (for 05)
        (log: data/temp/logs/00_text_features.log, written by 00_main.do)

Used by 05_descriptives_rq.do (research-question descriptives). A dictionary approach:
no model, no training data. Every feature is a robota.ua tag or a hand-written regular
expression (Ukrainian and Russian, some English). Full codebook: Project/README.md, section 8.

  Step 1. robota.ua clusters (clusters_json), prefix cl_: tags robota.ua attaches to
          each vacancy; the same tagger runs on every vacancy, so the coding is uniform.
  Step 2. Text to search, normalized (see below).
  Step 3. Regular expressions on the TEXT (title + description), prefix tx_. Badges are
          NOT in the text (changed 14 Nov 2026): they are coded apart in step 4.
  Step 4. Badges (perk labels in extra_json), prefix bd_. robota.ua's own badges are in
          Russian ("Офис с генератором"); employers can add their own. Badge use changes a
          lot over time (any badge: 22% of 2020 vacancies, 50% of 2023, 33% of 2026), so
          badge flags are kept apart from text flags; 05 combines them where it says so.
  Step 5. Occupation of the title: ISCO-08 major (isco1) and sub-major (isco2) groups,
          through the KSE crosswalk (85 groups, 146 rules) plus robota additions.
  Step 6. Military ads: role (title) and unit type (employer name).

Text normalization (step 2; fixed 14 Nov 2026):
  - lower case; every apostrophe form (’ ʼ ` ´ ‘) -> '; all whitespace (incl. the
    non-breaking spaces common in descriptions) -> one space;
  - Latin letters typed inside Cyrillic words (вiйськовий with a Latin i; o, a, e, c,
    p, x, y) -> Cyrillic.
  - All matching uses Python's re on object-dtype strings. pandas 3 stores text as Arrow
    strings, and str.contains on those runs RE2, where \\w and \\b match ASCII only: before
    the fix, every pattern with \\w or \\b (and no lookaround) silently missed Cyrillic.

Choices:
  - Experience: robota.ua's "Опыт работы" cluster (cl_exp: 0 = "no experience",
    0.5-5 = minimum years) and my own parse of "experience from N years" (tx_exp_years,
    the lowest N found, 0 < N <= 15). tx_exp_none = the ad says no experience is needed
    ("навчимо" alone no longer counts: it is training, tx_training).
  - Gender: an explicit search for women or men next to a hiring verb ("шукаємо
    дівчину", "запрошуємо жінок та чоловіків" sets both); plain mentions of "жінок" are
    too noisy. tx_fem_title = the title gives a feminine form ("водій/водійка",
    "вантажник(ця)").
  - Draft deferment (tx_defer): "бронювання"/"бронь"/"відстрочка" offered to workers.
    Dropped: booking (travel, hotels, restaurants) unless the ad also talks about
    mobilization; armored ("броньований", "бронированный"); payment deferral
    ("відстрочка платежу").
  - Shelter split (14 Nov 2026): tx_shelter_air (air-raid shelter) and tx_power
    (generator, Starlink, blackouts, backup power); tx_shelter = either, as before.
    Jobs ABOUT generators/Starlink/solar (title) do not count; nor does building shelters.
  - Age caps and gender words fall sharply in 2022 in all groups: likely platform
    moderation (Ukrainian law bans age and gender requirements in job ads), not employer
    behavior. Treat tx_age_cap and tx_*_seek as lower bounds.
"""
import json
import re
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

warnings.filterwarnings("ignore", message="This pattern is interpreted as a regular expression")

export = Path(sys.argv[1])
PROJECT = Path(__file__).resolve().parents[1]
XWALK = PROJECT / "data" / "crosswalks"
out = PROJECT / "data" / "temp" / "robota_text_features.csv"

cols = ["id", "name", "company_name", "description_text", "clusters_json",
        "languages_json", "extra_json"]
df = pq.read_table(export / "vacancies_with_text.parquet", columns=cols).to_pandas()
print(f"{len(df):,} vacancies from {export.name}")

# --- Step 1. robota.ua clusters ------------------------------------------------------
EXP = {"Без опыта": 0, "Опыт работы от 6 месяцев": 0.5, "Опыт работы от 1 года": 1,
       "Опыт работы от 2 лет": 2, "Опыт работы от 3 лет": 3, "Опыт работы от 4 лет": 4,
       "Опыт работы от 5 лет": 5}
EDU = {"Среднее образование": 1, "Середня спеціальна освіта": 2,
       "Неоконченное высшее образование": 3, "Высшее образование": 4}
SOFT = {"ПО", "Язык программирования", "Система автоматизации", "Графический редактор",
        "База данных", "Операционная система", "ПО для финансовой / экономической сферы",
        "Инструменты в интернет-маркетинге", "Инструменты аналитики данных"}


def clusters(cj, lj):
    r = dict(cl_exp=None, cl_edu=None, cl_english=0, cl_n_soft=0, cl_remote=0,
             cl_parttime=0, cl_intern=0, cl_rotation=0, cl_housing=0, cl_disab=0,
             cl_student=0, cl_pension=0, cl_veteran=0, cl_lic_c=0)
    soft = set()
    for c in json.loads(cj or "[]"):
        name = c.get("name", "").strip()
        groups = [g.get("name", "").strip() for g in c.get("groups", [])]
        if name == "Опыт работы":
            vals = [EXP[g] for g in groups if g in EXP]
            if vals:
                r["cl_exp"] = max(vals)
        elif name == "Образование":
            vals = [EDU[g] for g in groups if g in EDU]
            if vals:
                r["cl_edu"] = max(vals)
        elif name == "Знание языка":
            r["cl_english"] = int("Английский язык" in groups)
        elif name in SOFT:
            soft.update(groups)
        elif name == "Вид занятости":
            r["cl_remote"] = int("Удаленная работа" in groups)
            r["cl_parttime"] = int("Неполная занятость" in groups)
            r["cl_intern"] = int("Стажировка/практика" in groups)
            r["cl_rotation"] = int("Вахта" in groups)
        elif name == "Дополнительные сведения":
            r["cl_housing"] = int("Проживание обеспечивает работодатель" in groups)
            r["cl_disab"] = int("Работа для людей с инвалидностью" in groups)
            r["cl_student"] = int("Работа для студента" in groups)
            r["cl_pension"] = int("Работа для пенсионеров" in groups)
            r["cl_veteran"] = int("Ветеран" in groups)
        elif name == "Категория водительских прав":
            r["cl_lic_c"] = int(any(g.startswith("Права категории С") for g in groups))
    r["cl_n_soft"] = len(soft)
    for lang in json.loads(lj or "[]"):
        if isinstance(lang, dict) and lang.get("languageId") == 1:   # assumed: 1 = English
            r["cl_english"] = 1
    return r


feat = pd.DataFrame([clusters(c, l) for c, l in zip(df.clusters_json, df.languages_json)])
feat.insert(0, "id", df.id.values)

# --- Step 2. Text to search ---------------------------------------------------------
CYR = "а-яіїєґё"
HOMO = str.maketrans({"i": "і", "o": "о", "a": "а", "e": "е", "c": "с", "p": "р",
                      "x": "х", "y": "у"})
RX_HOMO = re.compile(rf"(?<=[{CYR}])[ioaecpxy]+(?=[{CYR}])|(?<=[{CYR}])[ioaecpxy]+(?=')"
                     rf"|(?<=')[ioaecpxy]+(?=[{CYR}])")


def norm(s):
    s = str(s or "").lower()
    s = re.sub("[’ʼ`´‘]", "'", s)
    s = re.sub(r"\s+", " ", s)
    return RX_HOMO.sub(lambda m: m.group(0).translate(HOMO), s)


def badges(ej):
    try:
        return " | ".join(b.get("name", "") for b in json.loads(ej or "{}").get("badges", []))
    except (ValueError, AttributeError):
        return ""


# object dtype on purpose: pandas then uses Python's re (see the docstring)
title = pd.Series([norm(s) for s in df.name], dtype=object)
text = pd.Series([norm(t) + " | " + norm(d) for t, d in zip(df.name, df.description_text)],
                 dtype=object)
badge = pd.Series([norm(badges(e)) for e in df.extra_json], dtype=object)
company = pd.Series([norm(s) for s in df.company_name], dtype=object)

# Language of the ad: 1 Ukrainian, 2 Russian, 3 English, 0 unclear. Letters only Ukrainian
# (іїєґ) or only Russian (ыэъё) use; English if most letters are Latin.
n_ua = text.str.count(r"[іїєґ]")
n_ru = text.str.count(r"[ыэъё]")
n_lat = text.str.count(r"[a-z]")
n_cyr = text.str.count(rf"[{CYR}]")
lang = pd.Series(0, index=df.index)
lang[(n_ua > 3 * n_ru) & (n_ua > 0)] = 1
lang[(n_ru > 3 * n_ua) & (n_ru > 0)] = 2
lang[n_lat > 2 * n_cyr] = 3
feat["tx_lang"] = lang.values

# --- Step 3. Regular expressions on the text ----------------------------------------
B = rf"(?<![{CYR}a-z])"          # word start
E = rf"(?![{CYR}a-z])"           # word end


def has(pattern, s=text):
    return s.str.contains(pattern, regex=True).astype("int8")


def drop(pattern, s=text):
    """The text with the phrases matching pattern blanked out (exclusions)."""
    rx = re.compile(pattern)
    return pd.Series([rx.sub(" ", t) for t in s], index=s.index, dtype=object)


# 3a. Experience
exp_none = has(r"без досвіду|без опыта|досвід\w* (роботи )?не (обов|потріб)|опыт\w* (работы )?не "
               r"(обяз|нуж|треб)|можна без досвіду|можно без опыта|no experience|experience is not required")
exp_none_neg = has(r"без (досвіду|опыта)[^.|]{0,25}не (розгляда|рассматр|підійд|подойд)")
feat["tx_exp_none"] = (exp_none & (1 - exp_none_neg)).astype("int8")

WORDNUM = {"пів": 0.5, "півроку": 0.5, "полугода": 0.5, "року": 1, "рік": 1, "одного": 1,
           "года": 1, "год": 1, "двох": 2, "двух": 2, "трьох": 3, "трех": 3, "трёх": 3,
           "чотирьох": 4, "четырех": 4, "п'яти": 5, "пяти": 5}
re_years = [
    re.compile(r"(?:досвід\w*|опыт\w*)(?:[^.\n;|]{0,40}?)\s(?:від|не менше|понад|більше|мінімум"
               r"|от|не менее|более|минимум)\s*(\d{1,2}(?:[.,]5)?|пів|півроку|полугода|року|рік|"
               r"одного|года|год|двох|двух|трьох|трех|трёх|чотирьох|четырех|п'яти|пяти)"
               r"\s*(?:[-–]\s*\d+\s*)?(рок|рік|р\.|міс|год|лет|мес)?"),
    re.compile(r"(\d{1,2})\+?\s*(?:[-–]\s*\d+\s*)?(рок|рік|років|роки|лет|года|год|years?)\w*\s+"
               r"(?:of\s+)?(?:\w+\s+){0,2}(?:досвід|опыт|experience)"),
    re.compile(r"(?:experience)\s*(?:of\s+)?(?:at least\s+|from\s+|min\.?\s+)?(\d{1,2})\+?\s*(years?)"),
]


def exp_years(s):
    best = None
    for rx in re_years:
        for m in rx.finditer(s):
            raw, unit = m.group(1), (m.group(2) or "")
            v = WORDNUM.get(raw)
            if v is None:
                try:
                    v = float(raw.replace(",", "."))
                except ValueError:
                    continue
            if unit.startswith(("міс", "мес")):
                v = v / 12
            if raw in ("пів",) and unit.startswith(("рок", "рік", "год", "лет")):
                v = 0.5
            if 0 < v <= 15:
                best = v if best is None else min(best, v)
    return best


feat["tx_exp_years"] = text.map(exp_years)

# 3b. Education, languages, training
higher = has(r"вищ(а|у|ої|ій|ою)\s+(\w+\s+){0,2}освіт|высш(ее|его|ем|им)\s+(\w+\s+){0,2}образован|"
             r"higher education|bachelor|бакалавр|магістр|магистр|master'?s degree")
incomplete = has(r"незакінчен\w* вищ|неповн\w* вищ|неоконченн\w* высш|незаконченн\w* высш")
feat["tx_higher_ed"] = (higher & (1 - incomplete)).astype("int8")
feat["tx_english"] = has(r"англійськ|английск|english|upper.?intermediate|pre.?intermediate|"
                         r"intermediate|ielts|toefl")
# training the employer gives the new hire (not "навчання" in general: duties, studies)
feat["tx_training"] = has(r"навчимо|научим|навчання (за рахунок|від компанії|на робочому місці)|"
                          r"обучение (за сч[её]т|от компании|на рабочем месте)|(безкоштовн|оплачуван|"
                          r"платн)\w* (навчанн|стажуванн)|(бесплатн|оплачиваем)\w* (обучени|стажировк)|"
                          r"корпоративн\w* (навчанн|обучени|університет|университет)|стажуванн|"
                          r"стажировк|наставни|менторств|навча\w* з нуля|обуча\w* с нуля|"
                          r"програм\w* (навчанн|адаптац|обучени)|training program|paid training")

# 3c. Gender: explicit search next to a hiring verb
VERB = (r"(?:шукаємо|шукаю|потрібен|потрібна|потрібні|потрібно|запрошуємо|запрошує|розглядаємо|"
        r"приймаємо|чекаємо|візьмемо|беремо|ищем|ищу|требуется|требуются|нужен|нужна|нужны|"
        r"приглашаем|рассматриваем|примем|возьмем|возьмём)")
FEM = r"(?:жінок|жінку|жінки|дівчат|дівчину|дівчина|женщин|женщину|девушек|девушку|девушка)"
MAL = r"(?:чоловіків|чоловіка|чоловіки|хлопців|хлопця|хлопець|мужчин|мужчину|парней|парня|парень)"
WORDS = r"\s+(?:[\w'-]+[\s,]+){0,4}?"
feat["tx_female_seek"] = has(VERB + WORDS + FEM + E + r"|стать:?\s*жіноча|пол:?\s*женский|"
                             r"(?:тільки|лише|только)\s+(?:для\s+)?" + FEM + E)
feat["tx_male_seek"] = has(VERB + WORDS + MAL + E + r"|стать:?\s*чоловіча|пол:?\s*мужской|"
                           r"(?:тільки|лише|только)\s+(?:для\s+)?" + MAL + E +
                           r"|" + B + r"чоловік віком|мужчина в возрасте|мужчина от \d\d")
# feminine form of the job title next to the masculine one. Three ways:
#   (i)  a feminine suffix after "/" or "(": "Касир(ка)", "Координатор/ка", "Помічник/ця"
#   (ii) a slash pair sharing the stem: "Водій/Водійка", "Оператор / Операторка"
#   (iii) a known feminine form of a job written alone ("Водійка вантажного авто")
FEM_SUFFIX = r"[/(]\s*-?\s*(?:ка|ця|иця|ниця|чиня|иня|кіня|киня|іня)(?![а-яіїєґ])"
FEM_END = re.compile(r"(?:ка|иця|ниця|чиня|иня|кіня|киня|ця)$")
FEM_FORMS = (r"водійк|вантажниц|комплектувальниц|комірниц|охоронниц|зварювальниц|слюсарк|"
             r"токарк|монтажниц|електрикин|кранівниц|трактористк|фрезерувальниц|пакувальниц|"
             r"продавчин|кухарк|операторк|менеджерк|бухгалтерк|директорк|адміністраторк|"
             r"розробниц|інженерк|майстрин|технологин|механікин|різноробочниц")


def fem_pair(t):
    for m in re.finditer(r"([а-яіїєґ'-]{3,})\s*/\s*([а-яіїєґ'-]{3,})", t):
        w1, w2 = m.group(1).split("-")[0], m.group(2).split("-")[0]
        if len(w1) >= 4 and w2.startswith(w1[:4]) and len(w2) > len(w1) and FEM_END.search(w2):
            return 1
    return 0


feat["tx_fem_title"] = ((has(FEM_SUFFIX + "|" + FEM_FORMS, title) == 1)
                        | (title.map(fem_pair) == 1)).astype("int8")

# 3d. Groups targeted
feat["tx_veteran"] = has(B + r"(?:ветеран\w*|убд|учасник\w* бойових|участник\w* боевых)")
feat["tx_disab"] = has(r"інвалідніст|инвалидност|з інвалідн|с инвалидн|обмеженими можливост")
feat["tx_idp"] = has(B + r"впо" + E + r"|переселен|внутрішньо переміщ|внутренне перемещ")
feat["tx_student"] = has(r"студент")
feat["tx_pension"] = has(r"пенсіонер|пенсионер|пенсійного віку|пенсионного возраста")
# age 16-70 only; "дітей віком до 6 років" and the like are excluded
AGE = r"(?:1[6-9]|[2-6]\d|70)"
rx_age = re.compile(r"(?:віком|возраст\w*|вік)\s*(?:від\s*\d\d\s*)?до\s*" + AGE + r"(?!\d)|"
                    r"до\s*" + AGE + r"\s*(?:років|лет)|не старше\s*" + AGE + r"(?!\d)")
rx_child = re.compile(r"(?:діт|дитин|дет|ребен|школяр|учн)\w*[^.|]{0,20}$")


def age_cap(s):
    return int(any(not rx_child.search(s[max(0, m.start() - 30):m.start()])
                   for m in rx_age.finditer(s)))


feat["tx_age_cap"] = text.map(age_cap).astype("int8")

# 3e. Mobilization and draft deferment
# exclusions first: armored ("броньований автомобіль", "бронированный"), payment deferral
text_d = drop(r"броньован\w*|бронированн\w*|броньов\w*|бронежилет\w*|"
              r"(?:відстроч|отсроч)\w*\s+(?:\w+\s+)?(?:платеж|платіж|оплат|поставк)\w*")
defer_raw = has(r"бронюв|бронь|броню|бронир|відстрочк|отсрочк", text_d)
booking = has(r"(?:бронюванн|бронирован)\w*\s+(?:авіа|квитк|номер|тур|готел|столик|житла|залів|білет|"
              r"билет|отел|авиа|ресторан|місць|мест)|(?:менеджер|фахівець|спеціаліст|адміністратор|"
              r"агент|оператор|служб|відділ|хостес)\w*\s+(?:з\s+|по\s+|відділу\s+|служби\s+)?(?:бронюв|бронир)|"
              r"систем\w* бронюв|систем\w* бронир|онлайн.бронюв|amadeus|booking|travel", text_d)
mobil = has(r"мобіліз|мобилиз|військовозобов|военнообязан|тцк|бронюванн\w* (?:працівник|співробітник)|"
            r"бронь (?:для )?(?:працівник|співробітник)|критичн\w* (?:важлив|підприєм|інфраструкт)", text_d)
feat["tx_defer"] = (defer_raw & ((1 - booking) | mobil)).astype("int8")
feat["tx_critical"] = has(r"критично важлив\w* (?:підприєм|для (?:економ|оборон|держав))|"
                          r"критичн\w+ (?:для (?:економ|оборон|держав)|підприєм|інфраструкт)|"
                          r"критически важн\w* (?:предприят|для)")
feat["tx_milreg"] = has(r"військов\w+ квит|військово.облік|воинск\w+ уч[её]т|військовозобов|"
                        r"военнообязан|военн\w+ билет|резерв\s?\+|резерв ?плюс|reserve\s?\+")

# 3f. Adaptation to the war: shelters, power, remote work, relocation, housing
about_power = has(r"генератор|starlink|старлінк|старлинк|інвертор|инвертор|сонячн|солнечн|"
                  r"ecoflow|акумулятор|аккумулятор", title)          # jobs ABOUT these
text_s = drop(r"(?:будівництв|облаштуванн|спорудженн|будуємо|будувати|строительств)\w* (?:\w+ )?"
              r"(?:укритт|сховищ|укрыти|убежищ)\w*")
feat["tx_shelter_air"] = has(r"укритт|укрыти[ея]|укрытия|бомбосхов|бомбоубежищ|протирадіац|"
                             r"сховищ\w* (?:на території|у будівлі|в будівлі|на підприємств)", text_s)
feat["tx_power"] = (has(r"генератор(?!\w* (?:ідей|идей|лідів|лидов|контенту|трафік))|starlink|старлінк|"
                        r"старлинк|блекаут|блэкаут|без світла|відключен\w* (?:світла|електро)|"
                        r"автономн\w+ (?:живлен|електро)|резервн\w+ (?:живлен|електро)|"
                        r"безперебійн\w* (?:живлен|інтернет|електро|зв'яз)|бесперебойн\w*|"
                        + B + r"дбж" + E + r"|ecoflow") & (1 - about_power)).astype("int8")
feat["tx_shelter"] = (feat.tx_shelter_air | feat.tx_power).astype("int8")
feat["tx_remote"] = has(r"(?:віддален|дистанційн|удаленн|дистанционн)\w*\s+(?:робот|работ|формат|режим|"
                        r"зайнят)|(?:працювати|робота|работать|работа)\s+(?:віддалено|дистанційно|"
                        r"удал[её]нно|з дому|из дома)|remote|work from home|"
                        + B + r"(?:віддалено|удал[её]нно)" + E)
feat["tx_reloc"] = has(r"релокац|релокова|релоцир|переїхал\w* з|перевезл\w+ виробництв|"
                       r"переміщен\w+ підприєм|перенес\w+ виробництв|евакуйован\w* (?:підприєм|виробництв)")
text_h = drop(r"(?:місц\w*|место|за місцем)\s+проживан\w*|проживаюч\w*|проживающ\w*|"
              r"проживан\w* (?:в межах|в районі|поблизу|недалеко)")
feat["tx_housing"] = has(r"житл(?:о|а|ом|і|у)" + E + r"|жиль[её]|жилье|проживання|проживание|"
                         r"гуртожит|общежит|оренд\w* (?:житла|квартир)|аренд\w* (?:жилья|квартир)|"
                         r"компенсац\w* оренд|компенсац\w* аренд|оплат\w* оренд", text_h)

# --- Step 4. Badges (bd_) -----------------------------------------------------------
feat["bd_any"] = (badge != "").astype("int8")
feat["bd_shelter"] = has(r"бомбоубежищ|бомбосхов|укритт|укрыти", badge)
feat["bd_power"] = has(r"генератор|бесперебойн|безперебійн|starlink|старлінк", badge)
feat["bd_defer"] = has(r"бронир|бронюв|бронь|відстроч|отсроч", badge)
feat["bd_training"] = has(r"обучени|навчанн", badge)
feat["bd_housing"] = has(r"проживани|житл|жиль|общежит|гуртож", badge)
feat["bd_veteran"] = has(r"ветеран", badge)

# --- Step 5. Occupation of the title: ISCO-08 ------------------------------------------
# Same procedure as the KSE pipeline (an earlier Work.ua pipeline, step on occupations):
#   1. standardize the title (first 100 characters; one apostrophe and hyphen form;
#      "." between letters -> "-"; spaces collapsed; outer punctuation trimmed);
#   2. find the matching rules with the LOWEST priority number (0 generic -> AMBIG;
#      1 helpers and heads of a named function; 2 specific compounds; 3 engineers;
#      4 core occupation nouns);
#   3. one group at that priority -> classified (occ_status 1). Several groups -> keep the
#      ISCO level they share: 2-digit (status 2), 1-digit (status 3), none (4, ambiguous);
#      5 generic title (AMBIG); 6 no rule.
groups = pd.read_csv(XWALK / "occupation_groups.csv", dtype=str).set_index("occ_code")
rules = pd.concat([pd.read_csv(XWALK / "occupation_rules.csv", dtype=str),
                   pd.read_csv(XWALK / "occupation_rules_robota.csv", dtype=str)],
                  ignore_index=True)
rules["priority"] = rules.priority.astype(int)
rules = rules.sort_values("priority", kind="stable").reset_index(drop=True)
assert rules.occ_code.isin(groups.index).all(), "a rule points to an unknown occ_code"
g1, g2 = groups.isco1.fillna(""), groups.isco2.fillna("")


def std_title(t):
    t = str(t or "")[:100].lower()
    t = re.sub("[’ʼ`´‘]", "'", t)
    t = re.sub("[–—−]", "-", t)
    t = re.sub(r"(?<=[^\W\d_])\.(?=[^\W\d_])", "-", t)
    t = re.sub(r"\s+", " ", t)
    return re.sub(r"^[ .,;]+|[ .,;]+$", "", t)


tstd = pd.Series([std_title(t) for t in df.name], dtype=object)
u = pd.Series(tstd.unique(), dtype=object)
best_p = np.full(len(u), 99)
best_c = np.full(len(u), "", dtype=object)
tie_g, tie2, tie1 = (np.zeros(len(u), dtype=bool) for _ in range(3))
for r in rules.itertuples(index=False):
    m = u.str.contains(r.pattern, regex=True).to_numpy()
    same = m & (best_p == r.priority) & (best_c != r.occ_code)
    tie_g |= same
    tie2 |= same & (pd.Series(best_c).map(g2).fillna("").to_numpy() != g2.get(r.occ_code, ""))
    tie1 |= same & (pd.Series(best_c).map(g1).fillna("").to_numpy() != g1.get(r.occ_code, ""))
    new = m & (r.priority < best_p)
    best_c[new], best_p[new] = r.occ_code, r.priority
    tie_g[new] = tie2[new] = tie1[new] = False
status = np.full(len(u), 6)
status[(best_p < 99) & ~tie_g] = 1
status[(best_p < 99) & tie_g & ~tie2] = 2
status[(best_p < 99) & tie2 & ~tie1] = 3
status[(best_p < 99) & tie1] = 4
status[best_c == "AMBIG"] = 5
occ = pd.DataFrame({"tstd": u, "occ_status": status, "best": best_c})
occ["occ_code"] = occ.best.where(occ.occ_status == 1, "")
occ["isco1"] = pd.to_numeric(occ.best.map(g1).where(occ.occ_status.isin([1, 2, 3])), errors="coerce")
occ["isco2"] = pd.to_numeric(occ.best.map(g2).where(occ.occ_status.isin([1, 2])), errors="coerce")
occ = pd.DataFrame({"tstd": tstd}).merge(occ, on="tstd", how="left")
feat["occ_code"] = occ.occ_code.values
feat["occ_status"] = occ.occ_status.values
feat["isco1"] = occ.isco1.values
feat["isco2"] = occ.isco2.values

# --- Step 6. Military ads: role (title) and unit type (employer name) -----------------
ROLE = [
    (1, "Drones and unmanned systems", r"бпла|бпак|бпс|дрон|fpv|безпілот|нрк|роботизован|ударних|"
                                       r"оператор\w* бпс"),
    (2, "Medics", r"медик|санітар|фельдшер|лікар|медичн|медсестр|парамедик"),
    (3, "Combat (infantry, assault, artillery)", r"стрілець|гранатомет|кулемет|штурмов|піхотин|"
                                                 r"снайпер|вогнемет|розвідник|зенітник|командир|"
                                                 r"номер обслуги|мінометник|міномет|навідник|птрк|"
                                                 r"артилер|механік-водій|танкіст|десантник|"
                                                 r"морськ\w+ піхотин|оператор\w* зброї"),
    (4, "Drivers", r"водій|водитель"),
    (5, "Communications, EW, IT", r"зв'яз|радіотелефон|реб" + E + r"|рлс|радіо|" + B + r"it" + E +
                                  r"|айті|програміст|системн|кібер|телекомун|радар"),
    (6, "Engineering and trades", r"сапер|механік|електрик|машиніст|зварюв|ремонт|слюсар|інженер|"
                                  r"будівел|технік|майстер|кранівник|токар"),
    (7, "Support (cook, clerk, HR, psychologist)", r"кухар|діловод|бухгалтер|психолог|рекрутер|"
                                                   r"кадр|писар|логіст|склад|юрист|інструктор|"
                                                   r"фінанс|прибиральн|адміністрат|оператор call|"
                                                   r"оператор кол|капелан|юрисконсульт"),
]
role = pd.Series(0, index=df.index, dtype="int8")   # 0 = generic ("військовослужбовець") or other
for code, _, pat in reversed(ROLE):                  # reversed: the first in the list wins
    role[title.str.contains(pat, regex=True)] = code
feat["mil_role"] = role.values

UNIT = [   # first match wins
    (1, "TCC (draft offices)", r"тцк|територіальн\w* центр\w* комплектування|військкомат"),
    (2, "Drone forces", r"безпілот|бпс|бпла|птахи мадяра|рарог|ударних"),
    (3, "National Guard", r"нгу|національн\w+ гвард|азов|хартія|любарт|броп|оперативного призначення|"
                          r"відділення комплектування|ґреґіт|грегіт"),
    (4, "Assault, airborne, marines", r"штурм|десант|дшв|аеромобіл|морськ\w+ піхот|обрмп|омпб|"
                                      r"повітрянодесант|фордж|third assault|3 ошбр|ошбр"),
    (5, "Mechanized, tank, artillery", r"механіз|мехінізов|омбр|овмбр|танков|артилер|важка|"
                                       r"сухопутн|ок \"?(?:південь|північ|схід|захід)|оперативне командування"),
    (6, "Territorial defense", r"тро" + E + r"|територіальн\w+ оборон"),
    (7, "Border guard, police", r"прикордон|дпсу|поліц|лють|нацполіц"),
    (8, "Navy, air force, special forces, intelligence", r"вмс|військово-морськ|повітрян\w+ сил|"
                                                         r"гур|розвідк|сбу|ссо|спеціальних операцій|"
                                                         r"спеціального призначення"),
    (9, "Recruiting centers (other)", r"рекрут"),
]
unit = pd.Series(0, index=df.index, dtype="int8")   # 0 = other military employer
for code, _, pat in reversed(UNIT):
    unit[company.str.contains(pat, regex=True)] = code
feat["mil_unit"] = unit.values
feat["mil_1824"] = has(r"18\s*[-–]\s*24|контракт\w* 18")
feat["mil_choose"] = has(r"обери\w*|оберіть|обирай|самостійно обрати|вибрати підрозділ|вибір підрозділ|"
                         r"без тцк|переведенн|перевест|переведемо")

# --- Step 7. Save -------------------------------------------------------------------
numeric = ("id", "tx_exp_years", "cl_exp", "cl_edu", "isco1", "isco2", "occ_code", "occ_status")
for c in feat.columns:
    if c not in numeric:
        feat[c] = feat[c].astype("int8")
feat.to_csv(out, index=False)
flags = [c for c in feat.columns if c not in numeric and c not in ("tx_lang", "cl_n_soft", "mil_role", "mil_unit")]
print("0/1 flags, % of all vacancies:")
print((feat[flags].mean() * 100).round(2).to_string())
print("means among non-missing: " + ", ".join(
    f"{c} {feat[c].mean():.2f}" for c in ("cl_exp", "cl_edu", "tx_exp_years", "cl_n_soft")))
print("occ_status, %:", (feat.occ_status.value_counts(normalize=True).sort_index() * 100).round(1).to_dict())
print("isco1, % (missing = not classified):",
      (feat.isco1.value_counts(normalize=True, dropna=False).sort_index() * 100).round(1).to_dict())
print(f"written: {out}")

# value labels for Stata: written next to the data, read by 05_descriptives_rq.do
ISCO1 = {0: "Armed forces", 1: "Managers", 2: "Professionals",
         3: "Technicians and associate professionals", 4: "Clerical support workers",
         5: "Service and sales workers", 6: "Skilled agricultural, forestry, fishery",
         7: "Craft and related trades", 8: "Plant and machine operators, assemblers",
         9: "Elementary occupations"}
ISCO2 = {1: "Commissioned armed forces officers", 2: "Non-commissioned armed forces officers",
         3: "Armed forces, other ranks", 11: "Chief executives, senior officials",
         12: "Administrative and commercial managers", 13: "Production and specialized services managers",
         14: "Hospitality, retail and other services managers", 21: "Science and engineering professionals",
         22: "Health professionals", 23: "Teaching professionals", 24: "Business and administration professionals",
         25: "ICT professionals", 26: "Legal, social and cultural professionals",
         31: "Science and engineering associate professionals", 32: "Health associate professionals",
         33: "Business and administration associate professionals",
         34: "Legal, social, cultural associate professionals", 35: "ICT technicians",
         41: "General and keyboard clerks", 42: "Customer services clerks",
         43: "Numerical and material recording clerks", 44: "Other clerical support workers",
         51: "Personal service workers", 52: "Sales workers", 53: "Personal care workers",
         54: "Protective services workers", 61: "Market-oriented skilled agricultural workers",
         62: "Skilled forestry, fishery and hunting workers", 71: "Building and related trades",
         72: "Metal, machinery and related trades", 73: "Handicraft and printing workers",
         74: "Electrical and electronic trades", 75: "Food, wood, garment and other craft trades",
         81: "Stationary plant and machine operators", 82: "Assemblers",
         83: "Drivers and mobile plant operators", 91: "Cleaners and helpers",
         92: "Agricultural, forestry and fishery laborers",
         93: "Laborers in mining, construction, manufacturing, transport",
         94: "Food preparation assistants", 95: "Street and related sales and service workers",
         96: "Refuse workers and other elementary workers"}
STATUS = {1: "1 classified (one group)", 2: "2 groups share ISCO 2-digit", 3: "3 groups share ISCO 1-digit",
          4: "4 ambiguous (several occupations)", 5: "5 generic title", 6: "6 no rule"}
lab = ([("isco1", c, n) for c, n in ISCO1.items()] + [("isco2", c, n) for c, n in ISCO2.items()]
       + [("occ_status", c, n) for c, n in STATUS.items()]
       + [("mil_role", c, n) for c, n, _ in ROLE] + [("mil_role", 0, "Generic or other")]
       + [("mil_unit", c, n) for c, n, _ in UNIT] + [("mil_unit", 0, "Other military employer")])
pd.DataFrame(lab, columns=["var", "value", "label"]).to_csv(
    out.with_name("robota_text_features_labels.csv"), index=False)
