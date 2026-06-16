import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/document_history.dart';
import 'auth_service.dart';

/// Firestore service for managing document history.
///
/// Provides methods to:
/// - Save document processing history for logged-in users
/// - Save full results with summary and Q&A
/// - Retrieve user's document history
/// - Delete history entries
class FirestoreService {
  static FirestoreService? _instance;
  FirebaseFirestore? _firestore;
  bool _isInitialized = false;

  final AuthService _authService = AuthService.instance;

  FirestoreService._();

  static FirestoreService get instance {
    _instance ??= FirestoreService._();
    return _instance!;
  }

  /// Whether Firestore is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize Firestore
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _firestore = FirebaseFirestore.instance;
      _isInitialized = true;
      debugPrint('FirestoreService: Firestore initialized');
      return true;
    } catch (e) {
      debugPrint('FirestoreService: Failed to initialize Firestore: $e');
      return false;
    }
  }

  /// Get reference to user's history collection
  CollectionReference<Map<String, dynamic>>? _getUserHistoryCollection() {
    final userId = _authService.userId;
    if (userId == null || _firestore == null) return null;

    return _firestore!
        .collection('users')
        .doc(userId)
        .collection('history');
  }

  /// Save a document processing entry to user's history (basic info only)
  ///
  /// Only works for logged-in users. Returns the document ID if successful.
  Future<String?> saveDocumentHistory({
    required String fileName,
    required int fileSize,
    required int extractedTextLength,
    required String outputType,
    required String summaryLength,
    String outputLanguage = 'ar',
    int totalPages = 0,
    int fromPage = 1,
    int toPage = 0,
    String pageRangeLabel = 'كل الصفحات',
  }) async {
    // Only save for logged-in users
    if (_authService.isGuest) {
      debugPrint('FirestoreService: Skipping history save for guest user');
      return null;
    }

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('FirestoreService: Cannot save - Firestore not initialized');
        return null;
      }
    }

    try {
      final collection = _getUserHistoryCollection();
      if (collection == null) {
        debugPrint('FirestoreService: Cannot save - no user collection');
        return null;
      }

      final history = DocumentHistory(
        fileName: fileName,
        fileSize: fileSize,
        extractedTextLength: extractedTextLength,
        outputType: outputType,
        summaryLength: summaryLength,
        outputLanguage: outputLanguage,
        createdAt: DateTime.now(),
        totalPages: totalPages,
        fromPage: fromPage,
        toPage: toPage,
        pageRangeLabel: pageRangeLabel,
      );

      final docRef = await collection.add(history.toFirestore());
      debugPrint('FirestoreService: Document history saved: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('FirestoreService: Error saving document history: $e');
      return null;
    }
  }

  /// Save full result with summary and Q&A to user's history
  ///
  /// Only works for logged-in users. Returns the document ID if successful.
  Future<String?> saveFullResult({
    required String fileName,
    required int fileSize,
    required int extractedTextLength,
    required String outputType,
    required String summaryLength,
    String outputLanguage = 'ar',
    String? generatedSummary,
    List<Map<String, String>>? questionsAndAnswers,
    int totalPages = 0,
    int fromPage = 1,
    int toPage = 0,
    String pageRangeLabel = 'كل الصفحات',
  }) async {
    debugPrint('Save result started');

    // Only save for logged-in users
    if (_authService.isGuest) {
      debugPrint('FirestoreService: Skipping result save for guest user');
      return null;
    }

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('Save result failed: Firestore not initialized');
        return null;
      }
    }

    try {
      final collection = _getUserHistoryCollection();
      if (collection == null) {
        debugPrint('Save result failed: no user collection');
        return null;
      }

      final history = DocumentHistory(
        fileName: fileName,
        fileSize: fileSize,
        extractedTextLength: extractedTextLength,
        outputType: outputType,
        summaryLength: summaryLength,
        outputLanguage: outputLanguage,
        generatedSummary: generatedSummary,
        questionsAndAnswers: questionsAndAnswers,
        createdAt: DateTime.now(),
        totalPages: totalPages,
        fromPage: fromPage,
        toPage: toPage,
        pageRangeLabel: pageRangeLabel,
      );

      final docRef = await collection.add(history.toFirestore());
      debugPrint('Save result success: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('Save result failed: $e');
      return null;
    }
  }

  /// Get user's document history
  ///
  /// Returns empty list for guests or if Firestore is not available.
  /// Results are ordered by creation date (newest first).
  Future<List<DocumentHistory>> getDocumentHistory({int limit = 50}) async {
    // Return empty list for guests
    if (_authService.isGuest) {
      debugPrint('FirestoreService: No history for guest user');
      return [];
    }

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('FirestoreService: Cannot get history - Firestore not initialized');
        return [];
      }
    }

    try {
      final collection = _getUserHistoryCollection();
      if (collection == null) {
        debugPrint('FirestoreService: Cannot get history - no user collection');
        return [];
      }

      final querySnapshot = await collection
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final history = querySnapshot.docs
          .map((doc) => DocumentHistory.fromFirestore(doc))
          .toList();

      debugPrint('FirestoreService: Retrieved ${history.length} history entries');
      return history;
    } catch (e) {
      debugPrint('FirestoreService: Error getting document history: $e');
      return [];
    }
  }

  /// Get a single history entry by ID
  Future<DocumentHistory?> getHistoryById(String documentId) async {
    if (_authService.isGuest) return null;

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    try {
      final collection = _getUserHistoryCollection();
      if (collection == null) return null;

      final doc = await collection.doc(documentId).get();
      if (!doc.exists) return null;

      return DocumentHistory.fromFirestore(doc);
    } catch (e) {
      debugPrint('FirestoreService: Error getting history by ID: $e');
      return null;
    }
  }

  /// Delete a document history entry
  Future<bool> deleteDocumentHistory(String documentId) async {
    if (_authService.isGuest) return false;

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      final collection = _getUserHistoryCollection();
      if (collection == null) return false;

      await collection.doc(documentId).delete();
      debugPrint('FirestoreService: Document history deleted: $documentId');
      return true;
    } catch (e) {
      debugPrint('FirestoreService: Error deleting document history: $e');
      return false;
    }
  }

  /// Clear all document history for the current user
  Future<bool> clearAllHistory() async {
    if (_authService.isGuest) return false;

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      final collection = _getUserHistoryCollection();
      if (collection == null) return false;

      final querySnapshot = await collection.get();
      final batch = _firestore!.batch();

      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint('FirestoreService: All document history cleared');
      return true;
    } catch (e) {
      debugPrint('FirestoreService: Error clearing document history: $e');
      return false;
    }
  }
}
