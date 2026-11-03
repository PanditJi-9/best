"""Offline regressions for the source reachability report; no network calls."""

import sys
from pathlib import Path
import unittest
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import source_reachability as reach


class ReachabilityTest(unittest.TestCase):
    def test_mihon_index_is_unwrapped(self):
        index = {
            "extensionList": {
                "extensions": [
                    {
                        "packageName": "eu.kanade.tachiyomi.extension.ar.mangalek",
                        "sources": [
                            {"name": "مانجا ليك", "language": "ar",
                             "homeUrl": "https://lekmanga.online"},
                        ],
                    }
                ]
            }
        }

        sources = reach.collect_sources(index)

        self.assertEqual(len(sources), 1)
        self.assertEqual(sources[0]["url"], "https://lekmanga.online")
        self.assertEqual(sources[0]["language"], "ar")
        self.assertEqual(
            sources[0]["bundle"], "eu.kanade.tachiyomi.extension.ar.mangalek"
        )

    def test_aniyomi_index_uses_base_url_and_lang(self):
        index = [
            {
                "pkg": "eu.kanade.tachiyomi.animeextension.all.animeonsen",
                "sources": [
                    {"name": "AnimeOnsen", "lang": "all",
                     "baseUrl": "https://animeonsen.xyz"},
                ],
            }
        ]

        sources = reach.collect_sources(index)

        self.assertEqual(sources[0]["url"], "https://animeonsen.xyz")
        self.assertEqual(sources[0]["language"], "all")

    def test_a_source_without_a_url_is_not_a_host(self):
        index = [{"pkg": "p", "sources": [{"name": "x", "lang": "en"}]}]

        self.assertEqual(reach.collect_sources(index)[0]["url"], "")

    def test_an_http_error_still_proves_the_host_answers(self):
        def deny(request, timeout):
            raise urllib.error.HTTPError(
                request.full_url, 403, "Forbidden", {}, None
            )

        original = reach.urllib.request.urlopen
        reach.urllib.request.urlopen = deny
        try:
            self.assertEqual(reach.probe("https://example.test/"), (403, "http"))
        finally:
            reach.urllib.request.urlopen = original

    def test_a_connection_failure_is_unreachable(self):
        def fail(request, timeout):
            raise urllib.error.URLError("Name or service not known")

        original = reach.urllib.request.urlopen
        reach.urllib.request.urlopen = fail
        try:
            status, reason = reach.probe("https://gone.test/")
        finally:
            reach.urllib.request.urlopen = original

        self.assertEqual(status, 0)
        self.assertEqual(reason, "URLError")

    def test_a_missing_scheme_is_not_probed(self):
        self.assertEqual(reach.probe(""), (0, "no-url"))


if __name__ == "__main__":
    unittest.main()
