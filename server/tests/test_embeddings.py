"""
Unit tests for Embedding Service.
"""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent))


class TestEmbeddingServiceBasics(unittest.TestCase):
    """Test basic embedding service functionality without model."""

    def test_service_creation_without_model(self):
        """Test service can be created even without model installed."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            with patch.dict('sys.modules', {'sentence_transformers': None}):
                try:
                    service = EmbeddingService(cache_path=cache_path)
                    self.assertFalse(service.is_available())
                except ImportError:
                    pass

    def test_service_handles_empty_text(self):
        """Test service handles empty text gracefully."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            self.assertIsNone(service.embed_text(""))
            self.assertIsNone(service.embed_text("   "))

    def test_service_cosine_similarity(self):
        """Test cosine similarity calculation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            identical = [1.0, 0.0, 0.0]
            opposite = [-1.0, 0.0, 0.0]
            orthogonal = [0.0, 1.0, 0.0]
            
            self.assertAlmostEqual(service.cosine_similarity(identical, identical), 1.0, places=5)
            self.assertAlmostEqual(service.cosine_similarity(identical, opposite), -1.0, places=5)
            self.assertAlmostEqual(service.cosine_similarity(identical, orthogonal), 0.0, places=5)

    def test_service_embedding_cache(self):
        """Test embedding cache operations."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            service._cache = {
                "doc1_0": [0.1, 0.2, 0.3],
                "doc1_1": [0.4, 0.5, 0.6],
            }
            
            self.assertEqual(service.cache_size(), 2)
            self.assertEqual(service.get_embedding("doc1", 0), [0.1, 0.2, 0.3])
            self.assertEqual(service.get_embedding("doc1", 1), [0.4, 0.5, 0.6])
            self.assertIsNone(service.get_embedding("doc2", 0))

    def test_service_delete_embeddings(self):
        """Test deleting document embeddings."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            service._cache = {
                "doc1_0": [0.1, 0.2, 0.3],
                "doc1_1": [0.4, 0.5, 0.6],
                "doc2_0": [0.7, 0.8, 0.9],
            }
            
            count = service.delete_document_embeddings("doc1")
            
            self.assertEqual(count, 2)
            self.assertEqual(service.cache_size(), 1)
            self.assertIsNone(service.get_embedding("doc1", 0))
            self.assertEqual(service.get_embedding("doc2", 0), [0.7, 0.8, 0.9])

    def test_service_clear_cache(self):
        """Test clearing all embeddings."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            service._cache = {
                "doc1_0": [0.1, 0.2, 0.3],
                "doc2_0": [0.4, 0.5, 0.6],
            }
            
            count = service.clear_cache()
            
            self.assertEqual(count, 2)
            self.assertEqual(service.cache_size(), 0)

    def test_service_get_document_embeddings(self):
        """Test getting all embeddings for a document."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            service._cache = {
                "doc1_0": [0.1, 0.2, 0.3],
                "doc1_1": [0.4, 0.5, 0.6],
                "doc2_0": [0.7, 0.8, 0.9],
            }
            
            embeddings = service.get_document_embeddings("doc1")
            
            self.assertEqual(len(embeddings), 2)
            self.assertIn(0, embeddings)
            self.assertIn(1, embeddings)
            self.assertEqual(embeddings[0], [0.1, 0.2, 0.3])

    def test_service_find_similar(self):
        """Test finding similar chunks."""
        with tempfile.TemporaryDirectory() as tmpdir:
            cache_path = Path(tmpdir) / "embeddings_test.json"
            
            from server.services.embeddings import EmbeddingService
            
            service = EmbeddingService(cache_path=cache_path)
            
            service._cache = {
                "doc1_0": [1.0, 0.0, 0.0],
                "doc1_1": [0.0, 1.0, 0.0],
                "doc1_2": [0.0, 0.0, 1.0],
            }
            
            query = [0.9, 0.1, 0.0]
            similar = service.find_similar(query, "doc1", top_k=2)
            
            self.assertEqual(len(similar), 2)
            self.assertEqual(similar[0][0], 0)
            self.assertAlmostEqual(similar[0][1], 0.994, places=2)


class TestRAGStoreEmbeddingIntegration(unittest.TestCase):
    """Test RAG store integration with embeddings."""

    def test_rag_store_embedding_property(self):
        """Test RAG store has embedding service property."""
        from server.services.rag_store import LocalRAGStore, EMBEDDINGS_AVAILABLE
        
        with tempfile.TemporaryDirectory() as tmpdir:
            store_path = Path(tmpdir) / "test_store.json"
            store = LocalRAGStore(store_path=store_path)
            
            if EMBEDDINGS_AVAILABLE:
                self.assertIsNotNone(store.embeddings_service)
            else:
                self.assertIsNone(store.embeddings_service)
            
            self.assertFalse(store.is_embedding_available())

    def test_rag_store_index_with_embeddings_disabled(self):
        """Test RAG store indexing works without embeddings."""
        from server.services.rag_store import LocalRAGStore
        
        with tempfile.TemporaryDirectory() as tmpdir:
            store_path = Path(tmpdir) / "test_store.json"
            store = LocalRAGStore(store_path=store_path)
            
            result = store.index_document(
                title="Test Doc",
                text="This is a test document with some content for testing.",
                source="test",
                generate_embeddings=False
            )
            
            self.assertEqual(result["title"], "Test Doc")
            self.assertEqual(result["chunk_count"], 1)

    def test_rag_store_delete_cleans_embeddings(self):
        """Test RAG store delete cleans up embeddings."""
        from server.services.rag_store import LocalRAGStore
        
        with tempfile.TemporaryDirectory() as tmpdir:
            store_path = Path(tmpdir) / "test_store.json"
            store = LocalRAGStore(store_path=store_path)
            
            result = store.index_document(
                title="Test Doc",
                text="This is a test document with some content for testing.",
                source="test",
                generate_embeddings=False
            )
            
            doc_id = result["document_id"]
            
            result = store.delete_document(doc_id)
            
            self.assertTrue(result)


class TestHybridSearch(unittest.TestCase):
    """Test hybrid search functionality."""

    def test_query_lexical_only(self):
        """Test lexical query when embeddings unavailable."""
        from server.services.rag_store import LocalRAGStore
        
        with tempfile.TemporaryDirectory() as tmpdir:
            store_path = Path(tmpdir) / "test_store.json"
            store = LocalRAGStore(store_path=store_path)
            
            store.index_document(
                title="Test",
                text="machine learning artificial intelligence",
                generate_embeddings=False
            )
            
            results = store.query("artificial intelligence")
            
            self.assertGreater(len(results), 0)

    def test_query_hybrid_with_fallback(self):
        """Test hybrid query falls back to lexical."""
        from server.services.rag_store import LocalRAGStore
        
        with tempfile.TemporaryDirectory() as tmpdir:
            store_path = Path(tmpdir) / "test_store.json"
            store = LocalRAGStore(store_path=store_path)
            
            store.index_document(
                title="Test",
                text="machine learning artificial intelligence",
                generate_embeddings=False
            )
            
            results = store.query_hybrid("artificial intelligence")
            
            self.assertGreater(len(results), 0)
            self.assertIn("score", results[0])


if __name__ == "__main__":
    unittest.main()
