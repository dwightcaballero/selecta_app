import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/configuration.dart';

// ignore: constant_identifier_names
const String CONFIGURATIONS_COLLECTION_REF = 'configurations';
// ignore: constant_identifier_names
const String DEFAULT_CONFIG_DOC_ID = 'app_config';

class ConfigurationService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<Configuration> _configRef;

  ConfigurationService() {
    _configRef = _firestore
        .collection(CONFIGURATIONS_COLLECTION_REF)
        .withConverter<Configuration>(
          fromFirestore: (snapshots, _) {
            final data = snapshots.data();
            if (data == null) return Configuration.empty();
            return Configuration.fromJson(data);
          },
          toFirestore: (config, _) => config.toJson(),
        );
  }

  Stream<Configuration?> getConfigurationStream([String docId = DEFAULT_CONFIG_DOC_ID]) {
    return _configRef.doc(docId).snapshots().map((snapshot) => snapshot.data());
  }

  Future<Configuration> getConfiguration([String docId = DEFAULT_CONFIG_DOC_ID]) async {
    final doc = await _configRef.doc(docId).get();
    return doc.data() ?? Configuration.empty();
  }

  Future<bool> configurationExists([String docId = DEFAULT_CONFIG_DOC_ID]) async {
    final doc = await _configRef.doc(docId).get();
    return doc.exists;
  }

  Future<void> saveConfiguration(Configuration config, [String docId = DEFAULT_CONFIG_DOC_ID]) async {
    await _configRef.doc(docId).set(config, SetOptions(merge: true));
  }
}
