import json
import random
from datetime import datetime

todayISO = "2026-02-25"
current_year = 2026

def make_record(queryText, intent, startYear, startMonth, endYear, endMonth, rangeType, placeQuery, placeType, answerStyle, needsClarification, clarificationQuestion, confidence, notes):
    return {
        "queryText": queryText,
        "intent": intent,
        "startYear": startYear,
        "startMonth": startMonth,
        "endYear": endYear,
        "endMonth": endMonth,
        "rangeType": rangeType,
        "placeQuery": placeQuery,
        "placeType": placeType,
        "answerStyle": answerStyle,
        "needsClarification": needsClarification,
        "clarificationQuestion": clarificationQuestion,
        "confidence": confidence,
        "notes": notes
    }

dataset = []

# Helpers
months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
month_nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
seasons = {"spring": (3, 5), "summer": (6, 8), "fall": (9, 11), "winter": (12, 2)}
years = [2022, 2023, 2024, 2025, 2026]

countries = ["japan", "korea", "france", "italy", "mexico", "canada", "spain", "uk"]
cities = ["tokyo", "seoul", "paris", "rome", "nyc", "new york city", "la", "los angeles", "london"]

trip_keywords = ["trip", "vacation", "여행", "adventure", "weekend", "getaway", "holiday", "photos", "camera roll", "memories", "trips"]
fillers_start = ["find my", "show me", "please find", "did i go on a", "can you show", "looking for", "i need", "get my", ""]
fillers_end = ["please", "thanks", ""]

def random_filler(is_question=False):
    if is_question:
        return random.choice(["did i go to", "was i in", "did we visit", "were there any trips to"])
    else:
        return random.choice(fillers_start)

# 1. Time only (35% = 140)
for _ in range(140):
    year = random.choice(years)
    sub_type = random.choice(["month", "season", "year", "relative", "mixed"])
    
    if sub_type == "month":
        m_idx = random.randint(0, 11)
        m_name = months[m_idx]
        q = f"{random_filler()} {random.choice(trip_keywords)} in {m_name} {year}".strip()
        dataset.append(make_record(q, "set_range", year, m_idx+1, year, m_idx+1, "month", None, "none", "confirm_range", False, None, 0.9, "Explicit month and year"))
        
    elif sub_type == "season":
        s_name = random.choice(list(seasons.keys()))
        s_start, s_end = seasons[s_name]
        q = f"{random_filler()} my {s_name} {year} {random.choice(trip_keywords)}".strip()
        if s_name == "winter":
            dataset.append(make_record(q, "set_range", year, 12, year+1, 2, "season", None, "none", "confirm_range", False, None, 0.9, "Winter spans across years"))
        else:
            dataset.append(make_record(q, "set_range", year, s_start, year, s_end, "season", None, "none", "confirm_range", False, None, 0.9, "Explicit season and year"))
            
    elif sub_type == "year":
        q = f"{random_filler()} {year} {random.choice(trip_keywords)}".strip()
        dataset.append(make_record(q, "set_range", year, 1, year, 12, "year", None, "none", "confirm_range", False, None, 0.95, "Full year scan"))
        
    elif sub_type == "relative":
        rel = random.choice(["last summer", "last year", "two years ago"])
        if rel == "last summer":
            q = f"{random_filler()} {rel} {random.choice(trip_keywords)}".strip()
            dataset.append(make_record(q, "set_range", 2025, 6, 2025, 8, "season", None, "none", "confirm_range", False, None, 0.9, "Relative last summer from 2026"))
        elif rel == "last year":
            q = f"{random_filler()} {rel}".strip()
            dataset.append(make_record(q, "set_range", 2025, 1, 2025, 12, "year", None, "none", "confirm_range", False, None, 0.9, "Relative last year from 2026"))
        else:
            q = f"{random_filler()} {rel} {random.choice(['trips', 'photos'])}".strip()
            dataset.append(make_record(q, "set_range", 2024, 1, 2024, 12, "year", None, "none", "confirm_range", False, None, 0.8, "Relative two years ago"))
            
    elif sub_type == "mixed":
        q = f"show {random.choice(trip_keywords)} from {year}-{random.randint(1,12):02d}".strip()
        m = int(q.split("-")[1])
        dataset.append(make_record(q, "set_range", year, m, year, m, "month", None, "none", "confirm_range", False, None, 0.95, "Mixed format YYYY-MM"))


# 2. Place plus time (35% = 140)
for _ in range(140):
    year = random.choice(years)
    is_city = random.choice([True, False])
    place = random.choice(cities) if is_city else random.choice(countries)
    p_type = "city" if is_city else "country"
    
    sub_type = random.choice(["month", "season", "year", "typo"])
    
    if sub_type == "month":
        m_idx = random.randint(0, 11)
        m_name = months[m_idx]
        q = f"{random_filler()} {place} {random.choice(trip_keywords)} in {m_name} {year}".strip()
        dataset.append(make_record(q, "set_range", year, m_idx+1, year, m_idx+1, "month", place, p_type, "confirm_range", False, None, 0.9, "Place and month"))
        
    elif sub_type == "season":
        s_name = random.choice(list(seasons.keys()))
        s_start, s_end = seasons[s_name]
        q = f"{random_filler()} {s_name} {year} {place} {random.choice(trip_keywords)}".strip()
        if s_name == "winter":
            dataset.append(make_record(q, "set_range", year, 12, year+1, 2, "season", place, p_type, "confirm_range", False, None, 0.9, "Place and winter"))
        else:
            dataset.append(make_record(q, "set_range", year, s_start, year, s_end, "season", place, p_type, "confirm_range", False, None, 0.9, "Place and season"))
            
    elif sub_type == "year":
        q = f"my {place} {random.choice(trip_keywords)} {year}".strip()
        dataset.append(make_record(q, "set_range", year, 1, year, 12, "year", place, p_type, "confirm_range", False, None, 0.95, "Place and full year"))
        
    elif sub_type == "typo":
        q = f"korea lst yr".strip() # Hardcoded typo example, but we'll randomize a bit
        q = f"{place} lst yr".strip()
        dataset.append(make_record(q, "set_range", 2025, 1, 2025, 12, "year", place, p_type, "confirm_range", False, None, 0.7, "Typo 'lst yr' mapped to 2025"))

# 3. Yes/No Queries (20% = 80)
for _ in range(80):
    year = random.choice(years)
    is_city = random.choice([True, False])
    place = random.choice(cities) if is_city else random.choice(countries)
    p_type = "city" if is_city else "country"
    
    q_start = random_filler(is_question=True)
    m_idx = random.randint(0, 11)
    
    has_time = random.choice([True, False])
    if has_time:
        q = f"{q_start} {place} in {year}?".strip()
        dataset.append(make_record(q, "query_place_presence", year, 1, year, 12, "year", place, p_type, "yes_no", False, None, 0.9, "Yes/no presence check with year"))
    else:
        q = f"{q_start} {place} {random.choice(['before', 'ever', 'at all'])}?".strip()
        dataset.append(make_record(q, "query_place_presence", None, None, None, None, "unknown", place, p_type, "yes_no", False, None, 0.8, "Yes/no presence check without time constraint"))

# 4. Ambiguous queries requiring clarification (10% = 40)
for i in range(40):
    is_city = random.choice([True, False])
    place = random.choice(cities) if is_city else random.choice(countries)
    p_type = "city" if is_city else "country"
    
    ambig_type = random.choice(["missing_time", "couple_summers_ago", "this_weekend", "end_of_year"])
    
    if ambig_type == "missing_time":
        q = f"{random_filler()} trips to {place}".strip()
        dataset.append(make_record(q, "ask_clarification", None, None, None, None, "unknown", place, p_type, "clarify", True, f"When did you visit {place.title()}?", 0.8, "Missing time constraint"))
    elif ambig_type == "couple_summers_ago":
        q = f"trips from a couple summers ago".strip()
        dataset.append(make_record(q, "ask_clarification", None, None, None, None, "unknown", None, "none", "clarify", True, "Do you mean Summer 2024?", 0.5, "Ambiguous 'couple summers ago'"))
    elif ambig_type == "this_weekend":
        q = f"find {place} trips this weekend".strip()
        dataset.append(make_record(q, "ask_clarification", None, None, None, None, "unknown", place, p_type, "clarify", True, "What month should I scan for this weekend?", 0.6, "Ambiguous 'this weekend' relative timeframe"))
    elif ambig_type == "end_of_year":
        q = f"end of 2024 trips to {place}".strip()
        # Edge case: "end of 2024" treat as Oct to Dec 2024 unless ambiguous, then clarify
        dataset.append(make_record(q, "ask_clarification", 2024, 10, 2024, 12, "custom", place, p_type, "clarify", True, "Do you mean October to December 2024?", 0.7, "Clarify what 'end of 2024' means"))

# Shuffle dataset
random.shuffle(dataset)

# Ensure exact 400 (we generated 140+140+80+40 = 400)
dataset = dataset[:400]

with open('trips_dataset.jsonl', 'w', encoding='utf-8') as f:
    for d in dataset:
        f.write(json.dumps(d, ensure_ascii=False) + '\\n')

print("Generated trips_dataset.jsonl with", len(dataset), "records.")
