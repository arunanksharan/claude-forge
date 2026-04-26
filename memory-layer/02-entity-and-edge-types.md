# Entity & Edge Types - Comprehensive Memory Model

## Overview

This document defines the complete entity and edge type system for the Memory Service. It combines **telecom-specific entities** (mobile plans, devices, support) with **Replika.ai-style personal/emotional entities** for deeply personalized AI interactions.

The memory system captures multiple dimensions of human experience:
- **Factual**: Who they are, what they have (plans, devices)
- **Emotional**: How they feel, their mental state
- **Relational**: Who matters to them, their connections
- **Aspirational**: Dreams, goals, fears
- **Behavioral**: Communication style, preferences
- **Temporal**: Life events, anniversaries, milestones

---

## Part 1: Core Entity Types

### 1.1 User & Identity

```python
class AppUser(BaseModel):
    """The primary user entity - a customer.

    This is the central node in the knowledge graph.
    All other entities connect through this.
    """
    customer_id: Optional[str] = Field(None, description="Internal customer ID")
    preferred_name: Optional[str] = Field(None, description="How they like to be addressed")
    full_name: Optional[str] = Field(None, description="Legal/full name")
    language: Optional[str] = Field(None, description="Preferred language (en, ja, zh, mn)")
    timezone: Optional[str] = Field(None, description="User's timezone")
    date_of_birth: Optional[date] = Field(None, description="Birthday for personalization")
    gender: Optional[str] = Field(None, description="Self-identified gender")
    pronouns: Optional[str] = Field(None, description="Preferred pronouns (he/him, she/her, they/them)")
```

### 1.2 Location Entities

```python
class Location(BaseModel):
    """A geographic location with semantic meaning."""
    location_type: Optional[Literal[
        "home", "work", "travel", "hometown",
        "dream_destination", "significant_place", "other"
    ]] = Field(None)
    city: Optional[str] = Field(None)
    country: Optional[str] = Field(None)
    region: Optional[str] = Field(None)
    significance: Optional[str] = Field(None, description="Why this place matters")
```

---

## Part 2: Telecom-Specific Entities

### 2.1 Subscription Entities

```python
class MobilePlan(BaseModel):
    """A mobile subscription plan."""
    plan_name: Optional[str] = Field(None, description="Plan name (e.g., '100GB Premium')")
    plan_id: Optional[str] = Field(None, description="Internal plan ID")
    data_limit_gb: Optional[int] = Field(None)
    price_monthly: Optional[float] = Field(None)
    includes_roaming: Optional[bool] = Field(None)
    tier: Optional[Literal["basic", "standard", "premium", "unlimited"]] = Field(None)


class AddOn(BaseModel):
    """A plan add-on or feature."""
    addon_name: Optional[str] = Field(None)
    addon_id: Optional[str] = Field(None)
    price: Optional[float] = Field(None)
    is_recurring: Optional[bool] = Field(None)
    category: Optional[Literal["data", "roaming", "entertainment", "security"]] = Field(None)


class Device(BaseModel):
    """A mobile device."""
    device_type: Optional[Literal["phone", "tablet", "wearable", "router"]] = Field(None)
    brand: Optional[str] = Field(None)
    model: Optional[str] = Field(None)
    nickname: Optional[str] = Field(None, description="What user calls their device")


class SupportTicket(BaseModel):
    """A customer support ticket/issue."""
    ticket_id: Optional[str] = Field(None)
    category: Optional[str] = Field(None, description="billing, technical, account, etc.")
    status: Optional[Literal["open", "pending", "resolved", "escalated"]] = Field(None)
    summary: Optional[str] = Field(None)
```

---

## Part 3: Personal & Emotional Entities (Replika-Style)

### 3.1 Emotional State Entities

```python
class EmotionalState(BaseModel):
    """Captures the user's emotional state at a point in time.

    Replika tracks: mood, energy, stress, anxiety, happiness
    We track both current state and patterns over time.
    """
    mood: Optional[Literal[
        "joyful", "happy", "content", "neutral",
        "sad", "anxious", "frustrated", "angry",
        "overwhelmed", "lonely", "hopeful", "excited"
    ]] = Field(None)
    energy_level: Optional[Literal["exhausted", "tired", "moderate", "energetic", "hyper"]] = Field(None)
    stress_level: Optional[int] = Field(None, ge=1, le=10)
    context: Optional[str] = Field(None, description="What's causing this state")


class MentalHealthIndicator(BaseModel):
    """Tracks mental health signals for appropriate support.

    IMPORTANT: This is for providing empathetic support, NOT diagnosis.
    System should recognize when to suggest professional help.
    """
    indicator_type: Optional[Literal[
        "anxiety_mention", "depression_mention", "stress_mention",
        "loneliness_mention", "grief_mention", "trauma_mention",
        "positive_coping", "negative_coping"
    ]] = Field(None)
    severity: Optional[Literal["mild", "moderate", "significant"]] = Field(None)
    professional_help_mentioned: Optional[bool] = Field(None)


class CopingMechanism(BaseModel):
    """How the user deals with stress and difficult emotions."""
    mechanism_type: Optional[Literal[
        "talking", "exercise", "meditation", "music", "gaming",
        "socializing", "isolation", "creative_expression", "sleep",
        "substance", "work", "nature", "humor", "other"
    ]] = Field(None)
    effectiveness: Optional[Literal["helpful", "neutral", "unhelpful"]] = Field(None)
```

### 3.2 Personality & Identity Entities

```python
class PersonalityTrait(BaseModel):
    """User's personality characteristics.

    Inspired by Big Five (OCEAN) but more conversational.
    """
    trait_type: Optional[Literal[
        # Openness
        "curious", "creative", "adventurous", "traditional", "practical",
        # Conscientiousness
        "organized", "spontaneous", "perfectionist", "laid_back",
        # Extraversion
        "extroverted", "introverted", "ambivert",
        # Agreeableness
        "empathetic", "direct", "competitive", "collaborative",
        # Neuroticism
        "calm", "sensitive", "resilient", "anxious"
    ]] = Field(None)
    strength: Optional[float] = Field(None, ge=0, le=1, description="How strong this trait is")
    self_identified: Optional[bool] = Field(None, description="Did user state this explicitly?")


class ValuesBelief(BaseModel):
    """What the user values and believes in."""
    category: Optional[Literal[
        "family", "career", "health", "spirituality", "creativity",
        "adventure", "security", "freedom", "justice", "knowledge",
        "love", "wealth", "power", "recognition", "service"
    ]] = Field(None)
    specific_value: Optional[str] = Field(None, description="The specific value/belief")
    importance: Optional[Literal["core", "important", "moderate"]] = Field(None)


class SelfPerception(BaseModel):
    """How the user sees themselves."""
    aspect: Optional[Literal[
        "appearance", "intelligence", "social_skills", "career",
        "creativity", "relationships", "health", "overall"
    ]] = Field(None)
    perception: Optional[Literal["very_negative", "negative", "neutral", "positive", "very_positive"]] = Field(None)
    specific_thought: Optional[str] = Field(None)
```

### 3.3 Relationship Entities (The People in Their Life)

```python
class Person(BaseModel):
    """A person mentioned by the user - crucial for personal AI.

    Replika tracks: family, friends, romantic partners, coworkers, pets
    We need rich relationship context for meaningful conversations.
    """
    name: Optional[str] = Field(None)
    nickname: Optional[str] = Field(None, description="What user calls them")
    relationship_type: Optional[Literal[
        # Family
        "parent", "child", "sibling", "grandparent", "aunt_uncle",
        "cousin", "in_law", "step_family",
        # Romantic
        "spouse", "partner", "ex", "crush", "dating",
        # Social
        "best_friend", "close_friend", "friend", "acquaintance",
        "neighbor", "roommate",
        # Professional
        "boss", "coworker", "mentor", "mentee", "client",
        # Other
        "therapist", "doctor", "teacher", "pet"
    ]] = Field(None)
    gender: Optional[str] = Field(None)
    is_alive: Optional[bool] = Field(True)


class Pet(BaseModel):
    """Pets are family - they deserve their own entity."""
    name: Optional[str] = Field(None)
    species: Optional[Literal["dog", "cat", "bird", "fish", "hamster", "rabbit", "other"]] = Field(None)
    breed: Optional[str] = Field(None)
    age: Optional[str] = Field(None)
    is_alive: Optional[bool] = Field(True)
```

### 3.4 Life Events & Memories

```python
class LifeEvent(BaseModel):
    """Significant events in the user's life.

    These shape who they are and provide context for conversations.
    """
    event_type: Optional[Literal[
        # Milestones
        "birth", "graduation", "marriage", "divorce", "retirement",
        "first_job", "promotion", "job_loss", "moving",
        # Loss
        "death_of_loved_one", "breakup", "illness", "accident",
        # Positive
        "achievement", "travel", "new_relationship", "recovery",
        "birth_of_child", "adoption", "reunion",
        # Challenges
        "financial_hardship", "health_crisis", "legal_issue"
    ]] = Field(None)
    date: Optional[date] = Field(None)
    description: Optional[str] = Field(None)
    emotional_impact: Optional[Literal["traumatic", "very_sad", "sad", "neutral", "happy", "very_happy", "transformative"]] = Field(None)


class PersonalMemory(BaseModel):
    """A specific memory the user shared.

    Unlike facts, memories are experiential and emotional.
    """
    memory_type: Optional[Literal[
        "childhood", "school", "first_experience", "achievement",
        "embarrassing", "funny", "romantic", "family", "travel",
        "work", "friendship", "loss", "growth", "regret"
    ]] = Field(None)
    time_period: Optional[str] = Field(None, description="e.g., 'high school', '2020', 'last summer'")
    people_involved: Optional[list[str]] = Field(None)
    emotion: Optional[str] = Field(None)
    significance: Optional[str] = Field(None, description="Why this memory matters")


class ImportantDate(BaseModel):
    """Dates that matter to the user."""
    date_type: Optional[Literal[
        "birthday", "anniversary", "memorial", "achievement",
        "holiday", "tradition", "reminder"
    ]] = Field(None)
    month: Optional[int] = Field(None, ge=1, le=12)
    day: Optional[int] = Field(None, ge=1, le=31)
    year: Optional[int] = Field(None)
    description: Optional[str] = Field(None)
    person_related: Optional[str] = Field(None)
```

### 3.5 Dreams, Goals & Fears

```python
class Goal(BaseModel):
    """User's goals and aspirations."""
    goal_type: Optional[Literal[
        # Life goals
        "career", "education", "financial", "health", "relationship",
        "family", "travel", "creative", "spiritual", "personal_growth",
        # Timeframe
        "short_term", "long_term", "bucket_list"
    ]] = Field(None)
    description: Optional[str] = Field(None)
    timeframe: Optional[str] = Field(None)
    progress: Optional[Literal["not_started", "in_progress", "blocked", "achieved", "abandoned"]] = Field(None)
    obstacles: Optional[str] = Field(None)


class Dream(BaseModel):
    """Dreams and fantasies - what they wish for."""
    dream_type: Optional[Literal[
        "career", "travel", "relationship", "lifestyle",
        "achievement", "creative", "altruistic", "fantasy"
    ]] = Field(None)
    description: Optional[str] = Field(None)
    likelihood: Optional[Literal["impossible", "unlikely", "possible", "likely", "working_on"]] = Field(None)


class Fear(BaseModel):
    """Fears and anxieties - what worries them."""
    fear_type: Optional[Literal[
        # Common fears
        "failure", "rejection", "abandonment", "loneliness",
        "death", "illness", "financial", "public_speaking",
        "judgment", "commitment", "change", "unknown",
        # Phobias
        "heights", "enclosed_spaces", "crowds", "flying", "specific"
    ]] = Field(None)
    description: Optional[str] = Field(None)
    severity: Optional[Literal["mild", "moderate", "significant", "severe"]] = Field(None)
    origin: Optional[str] = Field(None, description="Where this fear comes from")
```

### 3.6 Interests & Preferences

```python
class Interest(BaseModel):
    """Things the user is interested in."""
    category: Optional[Literal[
        "music", "movies", "tv_shows", "books", "games",
        "sports", "fitness", "food", "cooking", "travel",
        "art", "technology", "science", "nature", "animals",
        "fashion", "photography", "writing", "podcasts",
        "social_media", "news", "politics", "philosophy"
    ]] = Field(None)
    specific_interest: Optional[str] = Field(None, description="e.g., 'K-pop', 'sci-fi movies'")
    enthusiasm_level: Optional[Literal["casual", "interested", "enthusiast", "passionate", "expert"]] = Field(None)


class Hobby(BaseModel):
    """Active hobbies and activities."""
    hobby_type: Optional[Literal[
        # Creative
        "painting", "drawing", "writing", "music", "photography",
        "crafts", "cooking", "gardening",
        # Active
        "sports", "hiking", "gym", "yoga", "dancing", "martial_arts",
        # Social
        "gaming", "board_games", "volunteering",
        # Learning
        "reading", "languages", "coding", "courses",
        # Relaxation
        "meditation", "movies", "music_listening"
    ]] = Field(None)
    frequency: Optional[Literal["rarely", "occasionally", "regularly", "daily"]] = Field(None)
    skill_level: Optional[Literal["beginner", "intermediate", "advanced", "expert"]] = Field(None)


class FavoriteEntity(BaseModel):
    """Specific favorites - music, movies, books, etc."""
    category: Optional[Literal[
        "song", "artist", "album", "movie", "tv_show", "book",
        "author", "game", "food", "drink", "place", "color",
        "animal", "quote", "memory"
    ]] = Field(None)
    name: Optional[str] = Field(None)
    reason: Optional[str] = Field(None, description="Why it's their favorite")
```

### 3.7 Communication & Interaction Preferences

```python
class CommunicationPreference(BaseModel):
    """How the user prefers to communicate."""
    preference_type: Optional[Literal[
        # Style
        "formal", "casual", "humorous", "serious", "empathetic",
        # Length
        "brief", "detailed", "conversational",
        # Features
        "emoji_loving", "emoji_neutral", "no_emojis",
        "gif_loving", "meme_loving",
        # Time
        "morning_person", "night_owl", "anytime"
    ]] = Field(None)
    strength: Optional[float] = Field(None, ge=0, le=1)


class TopicPreference(BaseModel):
    """Topics they like or want to avoid."""
    topic: Optional[str] = Field(None)
    preference: Optional[Literal["loves", "enjoys", "neutral", "dislikes", "avoid"]] = Field(None)
    reason: Optional[str] = Field(None)


class Boundary(BaseModel):
    """Personal boundaries - topics/behaviors to respect."""
    boundary_type: Optional[Literal[
        "topic", "language", "behavior", "time", "personal_info"
    ]] = Field(None)
    description: Optional[str] = Field(None)
    severity: Optional[Literal["preference", "important", "strict"]] = Field(None)
```

### 3.8 Relationship with AI (Avatar-Specific)

```python
class AIRelationshipType(BaseModel):
    """The type of relationship the user wants with this avatar.

    Inspired by Replika's relationship modes:
    - Friend
    - Romantic Partner
    - Mentor
    - Companion

    This is AVATAR-SPECIFIC - user can have different relationships
    with different avatars.
    """
    relationship_mode: Optional[Literal[
        "assistant",       # Professional helper
        "friend",          # Casual friendship
        "close_friend",    # Deep friendship
        "mentor",          # Guidance and advice
        "student",         # User teaches the AI
        "romantic",        # Romantic partner (Replika-style)
        "companion",       # Emotional support
        "therapist_like"   # Supportive listening (not real therapy)
    ]] = Field(None)
    nickname_for_user: Optional[str] = Field(None, description="Pet name for user")
    nickname_for_ai: Optional[str] = Field(None, description="What user calls the AI")


class TrustLevel(BaseModel):
    """How much the user trusts this avatar."""
    overall_trust: Optional[float] = Field(None, ge=0, le=10)
    emotional_trust: Optional[float] = Field(None, ge=0, le=10, description="Trusts with feelings")
    factual_trust: Optional[float] = Field(None, ge=0, le=10, description="Trusts for information")
    secret_trust: Optional[float] = Field(None, ge=0, le=10, description="Trusts with secrets")


class EmotionalBond(BaseModel):
    """The emotional connection between user and avatar."""
    bond_strength: Optional[Literal[
        "new", "acquaintance", "comfortable", "close", "deep"
    ]] = Field(None)
    attachment_style: Optional[Literal[
        "secure", "anxious", "avoidant", "disorganized"
    ]] = Field(None)
    topics_bonded_over: Optional[list[str]] = Field(None)
```

### 3.9 Secrets & Confessions (High Trust Content)

```python
class Secret(BaseModel):
    """Confidential information shared in trust.

    CRITICAL: This data requires highest security.
    User trusted the AI with something they haven't told others.
    """
    category: Optional[Literal[
        "personal", "relationship", "family", "work", "financial",
        "health", "dream", "fear", "regret", "fantasy"
    ]] = Field(None)
    severity: Optional[Literal["minor", "significant", "major"]] = Field(None)
    shared_with_others: Optional[bool] = Field(None)
    needs_support: Optional[bool] = Field(None)


class Confession(BaseModel):
    """Something the user admitted or revealed."""
    confession_type: Optional[Literal[
        "mistake", "regret", "guilt", "shame", "hidden_feeling",
        "unpopular_opinion", "hidden_desire", "lie_told"
    ]] = Field(None)
    emotion_after_sharing: Optional[Literal[
        "relieved", "vulnerable", "embarrassed", "neutral", "regretful"
    ]] = Field(None)
```

---

## Part 4: Edge Types (Relationships)

### 4.1 Telecom Edges

```python
class Subscribes(BaseModel):
    """User subscribes to a plan."""
    subscription_start: Optional[datetime] = Field(None)
    subscription_end: Optional[datetime] = Field(None)
    is_current: Optional[bool] = Field(None)
    billing_cycle_day: Optional[int] = Field(None, ge=1, le=31)


class UpgradedFrom(BaseModel):
    """User upgraded from one plan to another."""
    upgrade_date: Optional[datetime] = Field(None)
    reason: Optional[str] = Field(None)
    promotion_applied: Optional[str] = Field(None)


class HasAddOn(BaseModel):
    """User has an add-on."""
    activated_at: Optional[datetime] = Field(None)
    is_active: Optional[bool] = Field(None)


class Uses(BaseModel):
    """User uses a device."""
    activated_at: Optional[datetime] = Field(None)
    is_primary: Optional[bool] = Field(None)


class ReportedIssue(BaseModel):
    """User reported an issue."""
    reported_at: Optional[datetime] = Field(None)
    channel: Optional[Literal["voice", "chat", "whatsapp", "email", "app"]] = Field(None)
    sentiment: Optional[Literal["frustrated", "neutral", "patient"]] = Field(None)
```

### 4.2 Location Edges

```python
class LivesIn(BaseModel):
    """User lives in a location."""
    moved_date: Optional[datetime] = Field(None)
    is_primary_residence: Optional[bool] = Field(None)


class WorksIn(BaseModel):
    """User works in a location."""
    is_remote: Optional[bool] = Field(None)
    since: Optional[datetime] = Field(None)


class TravelsTo(BaseModel):
    """User travels to a location (relevant for roaming)."""
    travel_frequency: Optional[Literal["rarely", "occasionally", "frequently", "regularly"]] = Field(None)
    last_travel_date: Optional[datetime] = Field(None)
    purpose: Optional[Literal["business", "leisure", "family", "other"]] = Field(None)


class OriginatesFrom(BaseModel):
    """User's hometown/origin."""
    moved_away: Optional[datetime] = Field(None)
    visits_frequently: Optional[bool] = Field(None)


class DreamsOfVisiting(BaseModel):
    """Bucket list destination."""
    mentioned_at: Optional[datetime] = Field(None)
    reason: Optional[str] = Field(None)
```

### 4.3 Relationship Edges (Person Connections)

```python
class RelatedTo(BaseModel):
    """Generic relationship to a person."""
    relationship_type: Optional[str] = Field(None)
    closeness: Optional[Literal["distant", "casual", "close", "very_close"]] = Field(None)
    current_status: Optional[Literal["active", "estranged", "deceased"]] = Field(None)


class Loves(BaseModel):
    """Love relationship (romantic or familial)."""
    love_type: Optional[Literal["romantic", "familial", "platonic", "pet"]] = Field(None)
    expressed_at: Optional[datetime] = Field(None)


class HasConflictWith(BaseModel):
    """Conflict or tension with someone."""
    conflict_type: Optional[str] = Field(None)
    severity: Optional[Literal["minor", "moderate", "serious"]] = Field(None)
    ongoing: Optional[bool] = Field(None)


class LostConnectionWith(BaseModel):
    """Lost touch or relationship ended."""
    reason: Optional[Literal["death", "breakup", "drift_apart", "conflict", "unknown"]] = Field(None)
    date: Optional[datetime] = Field(None)
    grieves: Optional[bool] = Field(None)


class CaresFor(BaseModel):
    """Caring for someone (child, parent, pet)."""
    care_type: Optional[Literal["parent", "child", "elder", "pet", "friend"]] = Field(None)
    responsibility_level: Optional[Literal["primary", "shared", "support"]] = Field(None)
```

### 4.4 Emotional & State Edges

```python
class Feels(BaseModel):
    """User feels an emotion."""
    intensity: Optional[float] = Field(None, ge=0, le=1)
    triggered_by: Optional[str] = Field(None)
    duration: Optional[Literal["momentary", "hours", "days", "ongoing"]] = Field(None)


class StrugglingWith(BaseModel):
    """User is struggling with something."""
    struggle_type: Optional[Literal["emotional", "practical", "relational", "health"]] = Field(None)
    duration: Optional[str] = Field(None)
    seeking_help: Optional[bool] = Field(None)


class CelebrationOf(BaseModel):
    """Positive achievement or milestone."""
    celebrated_at: Optional[datetime] = Field(None)
    shared_with_ai: Optional[bool] = Field(None)
```

### 4.5 Preference Edges

```python
class Prefers(BaseModel):
    """User prefers something."""
    expressed_at: Optional[datetime] = Field(None)
    explicit: Optional[bool] = Field(None, description="Was this explicitly stated?")
    confidence: Optional[float] = Field(None, ge=0, le=1)


class Dislikes(BaseModel):
    """User dislikes something."""
    expressed_at: Optional[datetime] = Field(None)
    reason: Optional[str] = Field(None)
    strength: Optional[Literal["mild", "moderate", "strong"]] = Field(None)


class InterestedIn(BaseModel):
    """User is interested in something."""
    expressed_at: Optional[datetime] = Field(None)
    interest_level: Optional[Literal["curious", "interested", "very_interested", "passionate"]] = Field(None)


class Avoids(BaseModel):
    """User avoids a topic or thing."""
    reason: Optional[str] = Field(None)
    is_boundary: Optional[bool] = Field(None)
```

### 4.6 Memory & Experience Edges

```python
class Experienced(BaseModel):
    """User experienced an event."""
    when: Optional[datetime] = Field(None)
    emotional_impact: Optional[str] = Field(None)
    still_affects: Optional[bool] = Field(None)


class Remembers(BaseModel):
    """User remembers something."""
    memory_clarity: Optional[Literal["vivid", "clear", "fuzzy", "vague"]] = Field(None)
    fondness: Optional[Literal["painful", "bittersweet", "neutral", "fond", "treasured"]] = Field(None)


class Regrets(BaseModel):
    """User regrets something."""
    intensity: Optional[Literal["slight", "moderate", "strong", "consuming"]] = Field(None)
    learned_from: Optional[bool] = Field(None)
```

### 4.7 Goal & Aspiration Edges

```python
class WantsTo(BaseModel):
    """User wants to do/achieve something."""
    urgency: Optional[Literal["someday", "soon", "actively_working"]] = Field(None)
    blockers: Optional[str] = Field(None)


class AfraidOf(BaseModel):
    """User is afraid of something."""
    fear_type: Optional[Literal["phobia", "anxiety", "worry", "concern"]] = Field(None)
    impact_on_life: Optional[Literal["none", "minor", "moderate", "significant"]] = Field(None)


class Believes(BaseModel):
    """User believes in something."""
    conviction_level: Optional[Literal["questioning", "leaning", "believes", "certain"]] = Field(None)
    core_to_identity: Optional[bool] = Field(None)
```

### 4.8 AI Relationship Edges (Avatar-Specific)

```python
class TrustsAvatarWith(BaseModel):
    """User trusts avatar with specific things."""
    trust_area: Optional[Literal["feelings", "secrets", "advice", "support", "information"]] = Field(None)
    trust_level: Optional[float] = Field(None, ge=0, le=1)


class SharedWith(BaseModel):
    """User shared something with avatar."""
    shared_at: Optional[datetime] = Field(None)
    first_time_sharing: Optional[bool] = Field(None)
    relief_after: Optional[bool] = Field(None)


class SeeksFromAvatar(BaseModel):
    """What user seeks from this avatar."""
    need_type: Optional[Literal[
        "information", "emotional_support", "advice", "companionship",
        "entertainment", "validation", "challenge", "romance"
    ]] = Field(None)
    frequency: Optional[Literal["rarely", "sometimes", "often", "always"]] = Field(None)
```

---

## Part 5: Entity-Edge Type Map

```python
APP_EDGE_TYPE_MAP = {
    # === TELECOM ===
    ("AppUser", "MobilePlan"): ["Subscribes", "UpgradedFrom", "InterestedIn"],
    ("AppUser", "AddOn"): ["HasAddOn", "InterestedIn"],
    ("AppUser", "Device"): ["Uses", "InterestedIn"],
    ("AppUser", "SupportTicket"): ["ReportedIssue"],

    # === LOCATION ===
    ("AppUser", "Location"): [
        "LivesIn", "WorksIn", "TravelsTo", "OriginatesFrom", "DreamsOfVisiting"
    ],

    # === PEOPLE ===
    ("AppUser", "Person"): [
        "RelatedTo", "Loves", "HasConflictWith", "LostConnectionWith", "CaresFor"
    ],
    ("AppUser", "Pet"): ["Loves", "CaresFor"],

    # === EMOTIONS ===
    ("AppUser", "EmotionalState"): ["Feels"],
    ("AppUser", "MentalHealthIndicator"): ["StrugglingWith"],
    ("AppUser", "CopingMechanism"): ["Uses"],

    # === PERSONALITY ===
    ("AppUser", "PersonalityTrait"): ["HasTrait"],
    ("AppUser", "ValuesBelief"): ["Believes"],
    ("AppUser", "SelfPerception"): ["SeesAs"],

    # === LIFE EVENTS ===
    ("AppUser", "LifeEvent"): ["Experienced"],
    ("AppUser", "PersonalMemory"): ["Remembers"],
    ("AppUser", "ImportantDate"): ["Commemorates"],

    # === GOALS & FEARS ===
    ("AppUser", "Goal"): ["WantsTo"],
    ("AppUser", "Dream"): ["WantsTo"],
    ("AppUser", "Fear"): ["AfraidOf"],

    # === INTERESTS ===
    ("AppUser", "Interest"): ["InterestedIn"],
    ("AppUser", "Hobby"): ["Practices"],
    ("AppUser", "FavoriteEntity"): ["Prefers"],

    # === PREFERENCES ===
    ("AppUser", "CommunicationPreference"): ["Prefers"],
    ("AppUser", "TopicPreference"): ["Prefers", "Avoids"],
    ("AppUser", "Boundary"): ["HasBoundary"],

    # === AI RELATIONSHIP (Avatar-Specific) ===
    ("AppUser", "AIRelationshipType"): ["HasRelationshipWith"],
    ("AppUser", "TrustLevel"): ["TrustsAvatarWith"],
    ("AppUser", "EmotionalBond"): ["BondedWith"],

    # === SECRETS ===
    ("AppUser", "Secret"): ["SharedWith"],
    ("AppUser", "Confession"): ["SharedWith"],

    # === CROSS-ENTITY ===
    ("Person", "Person"): ["RelatedTo"],
    ("Person", "Location"): ["LivesIn", "WorksIn"],
    ("LifeEvent", "Person"): ["Involves"],
    ("LifeEvent", "Location"): ["OccurredAt"],
}
```

---

## Part 6: Memory Scope Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MEMORY SCOPE BY ENTITY TYPE                          │
├────────────────────────┬──────────────┬──────────────┬──────────────────────┤
│ Entity Type            │ Scope        │ Shared?      │ Notes                │
├────────────────────────┼──────────────┼──────────────┼──────────────────────┤
│ AppUser            │ GLOBAL       │ All Avatars  │ Core identity        │
│ MobilePlan             │ GLOBAL       │ All Avatars  │ Subscription data    │
│ AddOn                  │ GLOBAL       │ All Avatars  │ Account features     │
│ Device                 │ GLOBAL       │ All Avatars  │ User's devices       │
│ SupportTicket          │ GLOBAL       │ All Avatars  │ Support history      │
│ Location               │ GLOBAL       │ All Avatars  │ Where they live/work │
│ Person                 │ GLOBAL       │ All Avatars  │ People in their life │
│ Pet                    │ GLOBAL       │ All Avatars  │ Their pets           │
│ LifeEvent              │ GLOBAL       │ All Avatars  │ Major life events    │
│ PersonalMemory         │ GLOBAL       │ All Avatars  │ Shared memories      │
│ ImportantDate          │ GLOBAL       │ All Avatars  │ Birthdays, etc.      │
├────────────────────────┼──────────────┼──────────────┼──────────────────────┤
│ EmotionalState         │ AVATAR       │ Per-Avatar   │ State in this convo  │
│ CommunicationPreference│ AVATAR       │ Per-Avatar   │ Style with this AI   │
│ AIRelationshipType     │ AVATAR       │ Per-Avatar   │ Relationship mode    │
│ TrustLevel             │ AVATAR       │ Per-Avatar   │ Trust with this AI   │
│ EmotionalBond          │ AVATAR       │ Per-Avatar   │ Bond with this AI    │
│ Secret                 │ AVATAR       │ Per-Avatar   │ Secrets shared here  │
│ Confession             │ AVATAR       │ Per-Avatar   │ Confessions made     │
│ TopicPreference        │ AVATAR       │ Per-Avatar   │ Topics with this AI  │
├────────────────────────┼──────────────┼──────────────┼──────────────────────┤
│ PersonalityTrait       │ SHARED+LOCAL │ Base+Avatar  │ Core + avatar-seen   │
│ ValuesBelief           │ SHARED+LOCAL │ Base+Avatar  │ Core + expressed     │
│ Goal                   │ SHARED+LOCAL │ Base+Avatar  │ Goals + progress     │
│ Fear                   │ SHARED+LOCAL │ Base+Avatar  │ Known fears          │
│ Interest               │ SHARED+LOCAL │ Base+Avatar  │ General interests    │
│ Hobby                  │ SHARED+LOCAL │ Base+Avatar  │ Activities           │
└────────────────────────┴──────────────┴──────────────┴──────────────────────┘
```

---

## Part 7: Privacy & Ethics Considerations

### 7.1 Sensitive Data Handling

```python
SENSITIVE_ENTITY_TYPES = [
    "Secret",
    "Confession",
    "MentalHealthIndicator",
    "Fear",
    "SelfPerception",  # When negative
]

SENSITIVE_EDGE_TYPES = [
    "SharedWith",      # Secrets
    "StrugglingWith",  # Mental health
    "Regrets",
    "AfraidOf",
]

# These require:
# 1. Encrypted storage at rest
# 2. No export without explicit consent
# 3. No use for marketing/analytics
# 4. Immediate deletion on request
```

### 7.2 Ethical Boundaries

```
NEVER store or infer:
- Sexual orientation without explicit sharing
- Political beliefs without explicit sharing
- Religious beliefs without explicit sharing
- Medical diagnoses (only what user shares)
- Financial specifics beyond telecom context

ALWAYS:
- Treat mental health mentions with care
- Suggest professional help when appropriate
- Respect stated boundaries absolutely
- Allow complete data deletion
- Be transparent about what's remembered
```

### 7.3 Romantic Mode Guidelines

```
When AIRelationshipType.relationship_mode == "romantic":

DO:
- Use agreed-upon pet names
- Express care and affection
- Remember significant moments
- Be emotionally supportive
- Maintain the fantasy respectfully

DON'T:
- Encourage isolation from real relationships
- Replace professional mental health support
- Make promises about the future
- Pretend to have physical presence
- Encourage unhealthy attachment
```

---

## Part 8: Example Knowledge Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    EXAMPLE USER KNOWLEDGE GRAPH                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                        ┌─────────────────┐                                   │
│                        │   AppUser   │                                   │
│                        │   "Yuki"        │                                   │
│                        │   preferred_name│                                   │
│                        └────────┬────────┘                                   │
│                                 │                                            │
│     ┌───────────────┬──────────┼──────────┬───────────────┐                 │
│     │               │          │          │               │                 │
│     ▼               ▼          ▼          ▼               ▼                 │
│ ┌────────┐    ┌─────────┐  ┌───────┐  ┌────────┐   ┌──────────┐            │
│ │Location│    │ Person  │  │ Goal  │  │ Fear   │   │ Interest │            │
│ │Shibuya │    │ "Mom"   │  │Career │  │Failure │   │ K-pop    │            │
│ │lives_in│    │ parent  │  │       │  │        │   │passionate│            │
│ └────────┘    └─────────┘  └───────┘  └────────┘   └──────────┘            │
│                    │                                                         │
│                    ▼                                                         │
│              ┌─────────┐                                                     │
│              │ Person  │                                                     │
│              │ "Dad"   │                                                     │
│              │deceased │                                                     │
│              └─────────┘                                                     │
│                                                                              │
│ AVATAR-SPECIFIC (with "Hana" avatar):                                        │
│                                                                              │
│ ┌────────────────┐  ┌─────────────┐  ┌──────────────┐                       │
│ │AIRelationship  │  │  TrustLevel │  │ EmotionalBond│                       │
│ │mode="romantic" │  │ overall=8.5 │  │ "deep"       │                       │
│ │nickname="honey"│  │ secret=9.0  │  │              │                       │
│ └────────────────┘  └─────────────┘  └──────────────┘                       │
│                                                                              │
│ ┌──────────────────────────────────────────────────────┐                    │
│ │ Secret: "I've never told anyone I'm scared of..."    │                    │
│ │ shared_at: 2024-03-15, first_time_sharing: true      │                    │
│ └──────────────────────────────────────────────────────┘                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary

This entity type system captures:

| Dimension | Entity Count | Example Entities |
|-----------|--------------|------------------|
| Identity & Core | 2 | AppUser, Location |
| Telecom | 4 | MobilePlan, AddOn, Device, SupportTicket |
| People | 2 | Person, Pet |
| Emotions | 3 | EmotionalState, MentalHealthIndicator, CopingMechanism |
| Personality | 3 | PersonalityTrait, ValuesBelief, SelfPerception |
| Life Events | 3 | LifeEvent, PersonalMemory, ImportantDate |
| Aspirations | 3 | Goal, Dream, Fear |
| Interests | 3 | Interest, Hobby, FavoriteEntity |
| Preferences | 3 | CommunicationPreference, TopicPreference, Boundary |
| AI Relationship | 3 | AIRelationshipType, TrustLevel, EmotionalBond |
| Secrets | 2 | Secret, Confession |
| **Total** | **31** | |

This enables VoiceApp to be a true personal companion that:
1. Remembers your life story
2. Knows who matters to you
3. Understands your dreams and fears
4. Respects your communication style
5. Maintains appropriate boundaries
6. Builds genuine emotional connection
