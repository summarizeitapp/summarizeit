# Article Extraction Bug Fix

## Problem

Two related issues with article extraction on news sites with continuous scrolling articles:

**Issue 1: Wrong Content**
- URL: https://sg.yahoo.com/news/cyclist-dies-accident-bus-admiralty-085200307.html
- Expected: Summary of cyclist accident article
- Actual: Summary of a different article about a tree falling on ECP
- Cause: Fallback selector grabbed ALL paragraphs including related articles

**Issue 2: Wrong Title**
- URL: https://sg.news.yahoo.com/thousands-passenger-planes-fixed-avoid-211001302.html
- Expected: "Airlines race to fix Airbus planes after warning solar radiation could cause pilots to lose control"
- Actual: "Cyclist dies after accident with bus in Admiralty Drive" (first article on page)
- Cause: Using `document.title` which doesn't change as you scroll through continuous articles

## Root Causes

**Content Issue:**
The fallback selector was too broad:
```javascript
document.querySelectorAll("article p, main p, p, h1, h2, h3, li")
```

This grabbed ALL paragraphs on the entire page, including:
- Related articles in sidebars
- Recommended stories sections
- Footer content
- Navigation text
- Advertisement text

**Title Issue:**
Always using `document.title` which:
- Doesn't change on continuous scroll pages
- Returns the page title, not the article title
- Isn't updated when viewing different articles on the same page

## Solution

Implemented a **hierarchical extraction strategy** with smart filtering:

### 1. Primary: Readability.js
Still uses Readability as the primary method (most reliable)

### 2. Fallback: Targeted Container Search
If Readability fails, searches for main article container using specific selectors in priority order:
- `article[role="article"]` - Semantic HTML5
- `article.article` - Common class pattern
- `main article` - Article within main
- `[role="main"] article` - ARIA role
- `article` - Generic article tag
- `main` - Main content area
- `[role="main"]` - ARIA main role
- `.article-body` - Common class
- `.post-content` - Blog pattern
- `.entry-content` - WordPress pattern

### 3. Title Extraction
When using fallback, also extracts the article title from the container:
- Searches for title-specific selectors (`h1[class*="title"]`, `h1[class*="headline"]`, etc.)
- Falls back to first `h1` in container
- Ensures title is at least 10 characters
- Prevents using page title when article title is available

### 4. Scoped Extraction
Once container is found, extracts ONLY from that container:
```javascript
mainContainer.querySelectorAll("p, h1, h2, h3, h4, li")
```

### 5. Last Resort: Smart Filtering
If no container found, gets all paragraphs but filters out:
- Sidebars (`aside`, `[class*="sidebar"]`, `[id*="sidebar"]`)
- Related articles (`[class*="related"]`, `[id*="related"]`)
- Recommendations (`[class*="recommend"]`, `[id*="recommend"]`)
- Ads (`[class*="ad-"]`, `[id*="ad-"]`)
- Headers, footers, navigation
- Short paragraphs (< 20 chars)

## Benefits

✅ **Accurate Content** - Extracts only the main article content
✅ **Correct Titles** - Extracts article title from container, not page title
✅ **Robust** - Multiple fallback strategies for both content and title
✅ **Clean** - Filters out sidebars and related content
✅ **Semantic** - Respects HTML5 structure and ARIA roles
✅ **Compatible** - Works across different site structures
✅ **Continuous Scroll** - Handles sites with multiple articles on same page

## Testing

Test on sites with multiple articles visible:
- News sites with "related stories" sidebars
- Blog posts with "recommended reading"
- Article pages with "trending now" sections
- Pages with multiple article previews

The extraction should now correctly identify and extract only the main article content.
