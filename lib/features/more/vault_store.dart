import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'more_store.dart';
import 'vault_crypto.dart';

class VaultStore{
  VaultStore._();static final instance=VaultStore._();SecretKey? _key;int _epoch=0;
  bool get unlocked=>_key!=null;
  void lock(){_epoch++;_key=null;}
  void _check(int epoch){if(_epoch!=epoch||_key==null)throw StateError('Vault is locked');}
  Future<bool> exists()async=>(await(await MoreStore.instance.db).query('vault_meta',where:'id=1')).isNotEmpty;
  Future<void> unlock(String password,{required bool create})async{
    final epoch=_epoch;
    final database=await MoreStore.instance.db;
    final rows=await database.query('vault_meta',where:'id=1');
    if(create&&rows.isNotEmpty)throw StateError('Vault already exists');
    if(!create&&rows.isEmpty)throw StateError('Vault unavailable');
    final meta=create?<String,dynamic>{'version':1,'iterations':600000,'salt':base64Encode(vaultRandom(16))}
      :jsonDecode(rows.first['payload'] as String) as Map<String,dynamic>;
    if(meta['version']!=1||meta['iterations']!=600000)throw StateError('Unsupported vault format');
    final bytes=List<int>.of(await compute(deriveVaultKey,{'password':password,'salt':meta['salt'] as String,'iterations':meta['iterations'] as int}));
    final key=SecretKey(List<int>.of(bytes));bytes.fillRange(0,bytes.length,0);
    if(epoch!=_epoch)throw StateError('Unlock cancelled');
    if(create){
      meta['check']=await encryptVaultJson({'marker':'daynest-vault-v1'},key,'daynest-vault-check-v1');
      if(epoch!=_epoch)throw StateError('Unlock cancelled');
      await database.insert('vault_meta',{'id':1,'payload':jsonEncode(meta)});
    }else{
      final check=await decryptVaultJson(meta['check'] as String,key,'daynest-vault-check-v1');
      if(check['marker']!='daynest-vault-v1')throw StateError('Invalid vault');
    }
    if(epoch!=_epoch)throw StateError('Unlock cancelled');_key=key;
  }
  Future<List<MoreRow>> entries()async{
    final epoch=_epoch;final key=_key;_check(epoch);
    final rows=await(await MoreStore.instance.db).query('vault_entries',orderBy:'id DESC');
    final result=<MoreRow>[];
    for(final r in rows){final id=r['id'] as int;
      final plain=await decryptVaultJson(r['payload'] as String,key!,'daynest-vault-v1:$id');_check(epoch);
      result.add({...plain,'id':id});}
    _check(epoch);return result;
  }
  Future<void> save(MoreRow value,{int? id})async{
    final epoch=_epoch;final key=_key;_check(epoch);
    if((value['title'] as String).trim().isEmpty||(value['password'] as String).isEmpty)throw ArgumentError('Title and password required');
    final database=await MoreStore.instance.db;
    await database.transaction((txn)async{
      _check(epoch);final recordId=id??await txn.insert('vault_entries',{'payload':''});
      final cipher=await encryptVaultJson(value,key!,'daynest-vault-v1:$recordId');_check(epoch);
      final changed=await txn.update('vault_entries',{'payload':cipher},where:'id = ?',whereArgs:[recordId]);
      if(changed!=1)throw StateError('Entry unavailable');
    });
  }
  Future<void> remove(int id)async{
    final epoch=_epoch;_check(epoch);final database=await MoreStore.instance.db;_check(epoch);
    await database.delete('vault_entries',where:'id = ?',whereArgs:[id]);
  }
}
