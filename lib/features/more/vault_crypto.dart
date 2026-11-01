import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

List<int> vaultRandom(int length){final random=Random.secure();return List.generate(length,(_)=>random.nextInt(256));}
Future<List<int>> deriveVaultKey(Map<String,Object?> input)async{
  final algorithm=Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:input['iterations'] as int,bits:256);
  final key=await algorithm.deriveKeyFromPassword(password:input['password'] as String,nonce:base64Decode(input['salt'] as String));
  return key.extractBytes();
}
Future<String> encryptVaultJson(Map<String,Object?> value,SecretKey key,String context)async{
  final box=await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(value)),secretKey:key,nonce:vaultRandom(12),aad:utf8.encode(context));
  return jsonEncode({'nonce':base64Encode(box.nonce),'cipher':base64Encode(box.cipherText),'mac':base64Encode(box.mac.bytes)});
}
Future<Map<String,Object?>> decryptVaultJson(String value,SecretKey key,String context)async{
  final data=jsonDecode(value) as Map<String,dynamic>;
  final box=SecretBox(base64Decode(data['cipher'] as String),nonce:base64Decode(data['nonce'] as String),mac:Mac(base64Decode(data['mac'] as String)));
  final bytes=await AesGcm.with256bits().decrypt(box,secretKey:key,aad:utf8.encode(context));
  return Map<String,Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
}
String generateVaultPassword({int length=20}){
  if(length<16||length>128)throw ArgumentError('Use 16–128 characters');
  const groups=['ABCDEFGHJKLMNPQRSTUVWXYZ','abcdefghijkmnopqrstuvwxyz','23456789','!@#%&*+-=?'];
  final random=Random.secure();final all=groups.join();
  final chars=[for(final group in groups)group[random.nextInt(group.length)]];
  while(chars.length<length){chars.add(all[random.nextInt(all.length)]);}
  for(var i=chars.length-1;i>0;i--){final j=random.nextInt(i+1);final temp=chars[i];chars[i]=chars[j];chars[j]=temp;}
  return chars.join();
}
