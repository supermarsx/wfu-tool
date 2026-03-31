# Tests for Get-SystemLanguageCode

$lang = Get-SystemLanguageCode

Assert-NotNull $lang 'Locale: Returns a non-null value'
Assert-Match '^\w{2}-\w{2,}$' $lang 'Locale: Matches xx-XX pattern'

# Should be a real language code
$knownLangs = @('en-US', 'en-GB', 'pt-BR', 'pt-PT', 'de-DE', 'fr-FR', 'es-ES', 'it-IT', 'nl-NL', 'ja-JP', 'zh-CN', 'zh-TW', 'ko-KR', 'ru-RU', 'ar-SA', 'pl-PL', 'cs-CZ', 'da-DK', 'fi-FI', 'nb-NO', 'sv-SE', 'hu-HU', 'tr-TR', 'el-GR', 'he-IL', 'th-TH', 'uk-UA', 'ro-RO', 'hr-HR', 'sk-SK', 'sl-SI', 'sr-Latn-RS', 'bg-BG', 'et-EE', 'lv-LV', 'lt-LT')
# We can't assert it's in the list (could be any valid locale) but it should have at least 4 chars
Assert-True ($lang.Length -ge 4) 'Locale: Length is at least 4 (xx-X)'

# Multiple calls should return the same value
$lang2 = Get-SystemLanguageCode
Assert-Equal $lang $lang2 'Locale: Consistent across calls'
