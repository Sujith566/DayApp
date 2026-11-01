import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import '../lib/features/more/vault_crypto.dart';

void main(){
  final key=SecretKey(List<int>.generate(32,(i)=>i));
  test('authenticated encryption round trip and independent nonces',()async{
    final value=<String,Object?>{'title':'Private account','password':'a very secret password'};
    final a=await encryptVaultJson(value,key,'daynest-vault-v1:1');
    final b=await encryptVaultJson(value,key,'daynest-vault-v1:1');
    expect(a,isNot(b));expect(a.contains('a very secret password'),isFalse);
    expect(await decryptVaultJson(a,key,'daynest-vault-v1:1'),value);
  });
  test('wrong key and swapped entry identity are rejected',()async{
    final encrypted=await encryptVaultJson({'password':'secret'},key,'daynest-vault-v1:1');
    await expectLater(decryptVaultJson(encrypted,SecretKey(List.filled(32,99)),'daynest-vault-v1:1'),throwsA(anything));
    await expectLater(decryptVaultJson(encrypted,key,'daynest-vault-v1:2'),throwsA(anything));
  });
  test('tampered authentication tag is rejected',()async{
    final encoded=await encryptVaultJson({'password':'secret'},key,'record');
    final payload=jsonDecode(encoded) as Map<String,dynamic>;
    final tag=base64Decode(payload['mac'] as String);tag[0]^=1;payload['mac']=base64Encode(tag);
    await expectLater(decryptVaultJson(jsonEncode(payload),key,'record'),throwsA(anything));
  });
  test('PBKDF2 SHA256 reference vector',()async{
    final bytes=await deriveVaultKey({'password':'password','salt':base64Encode(utf8.encode('salt')),'iterations':1});
    expect(bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join(),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
  });
  test('generated passwords have requested length and every character group',(){
    final seen=<String>{};
    for(var i=0;i<100;i++){
      final password=generateVaultPassword();expect(password.length,20);
      expect(RegExp(r'[A-Z]').hasMatch(password),isTrue);expect(RegExp(r'[a-z]').hasMatch(password),isTrue);
      expect(RegExp(r'[2-9]').hasMatch(password),isTrue);expect(RegExp(r'[!@#%&*+\-=?]').hasMatch(password),isTrue);
      seen.add(password);
    }
    expect(seen.length,100);
  });
}
