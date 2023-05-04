import 'dart:convert';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:vets_uo_dart_api/models/user.dart';
import 'package:vets_uo_dart_api/repositories/user_repository.dart';
import 'package:vets_uo_dart_api/encrypt_password.dart'as encrypter;
import 'package:vets_uo_dart_api/user_token_service.dart' as jwt_service;


final userRouter = Router()
  ..get('/users', _usersHandler)
  ..post('/users/signUp', _signUpHanler)
  ..post('/users/login', _loginHanler)
  ..get('/users/<id>', _getUserHanler)
  ..delete('/users/<id>', _getUserDeletionHandler)
  ..put('/users/<id>', _editUserHandler);

Future<Response> _usersHandler(Request request) async {
  final users = await UsersRepository.findAll();
  return Response.ok(json.encode(users));
}


Future<Response> _signUpHanler(Request request) async {
  final userRequestBody = await request.readAsString();
  final user = User.fromJson(json.decode(userRequestBody));
  final List<Map<String, String>> userValidateErrors = await validateUser(user);
  dynamic userCreated;
  if (userValidateErrors.isEmpty) {
    userCreated = await UsersRepository.insertOne(user);
    // if hubo un error al insertar el registro
    if (userCreated.containsKey("error")) userValidateErrors.add(userCreated);
  }
  if (userValidateErrors.isNotEmpty) {
    final encodedError = jsonEncode(userValidateErrors);
    return Response.badRequest(
        body: encodedError, headers: {'content-type': 'application/json'});
  } else {
    return Response.ok('Usuario creado correctamente $userCreated');
  }
}

validateUser(User user) async {
  List<Map<String, String>> errors = [];
  final userFound = await UsersRepository.findOne({"email": user.email});

  if (userFound != null) {
    errors.add({"email": "The user already exists with the same email"});
  }

  if (user.email.isEmpty) {
    errors.add({"email": "Email is a required field"});
  }
  if (user.name.isEmpty) {
    errors.add({"name": "Name is a required field"});
  }

  if (user.surname.isEmpty) {
    errors.add({"surname": "surname is a required field"});
  }

  if (user.password.isEmpty || user.password.length < 6) {
    errors.add({"surname": "Password should have at least 6 characters"});
  }
  return errors;
}


Future<Response> _getUserHanler(Request request) async {
  final dynamic token =
      request.headers.containsKey("token") ? request.headers["token"] : "";
  final Map<String, dynamic> verifiedToken =
      jwt_service.UserTokenService.verifyJwt(token);
  if (verifiedToken['authorized'] == false) {
    return Response.unauthorized(json.encode(verifiedToken));
  } else {
    dynamic userId = ObjectId.fromHexString(request.params['id'].toString());
    final users = await UsersRepository.findOne({"_id":userId});
    return Response.ok(json.encode(users));
  }
}

/*
Ponemos como parámetro del request el id, y de cuerpo los atributos que queramos cambiar. Se cambiarán solo los que se pongan, y si se quiere cambiar
el usuario, no se puede poner el mismo que ya había previamente
*/
Future<Response> _editUserHandler(Request request) async {
    final dynamic tokenValidation = validateToken(request);
    if (tokenValidation['authorized'] == false) {
      return Response.unauthorized(json.encode(tokenValidation));
    }

  dynamic userId = ObjectId.fromHexString(request.params['id'].toString());
  final users = await UsersRepository.findOne({"_id":userId});
     if (users == null) {
              return Response.ok('No existe un usuario con ese id');
     }
     else {
    final userRequestBody = await request.readAsString();
    final user = User.fromJson(json.decode(userRequestBody));
    final List<Map<String, String>> userValidateErrors = await validateUser(user);
    dynamic userCreated;
    if (userValidateErrors.isEmpty) {
          userCreated = await UsersRepository.update({"_id":userId}, user);
      if (userCreated.containsKey("error")) userValidateErrors.add(userCreated);
    }
    if (userValidateErrors.isNotEmpty) {
      final encodedError = jsonEncode(userValidateErrors);
      return Response.badRequest(
          body: encodedError, headers: {'content-type': 'application/json'});
    } else {
      return Response.ok('Usuario actualizado correctamente');
    }
  }
}

/*
Ponemos como parámetro del request el id del usuario que queramos borrar
*/
Future<Response> _getUserDeletionHandler(Request request) async {
  
    final dynamic tokenValidation = validateToken(request);
    if (tokenValidation['authorized'] == false) {
      return Response.unauthorized(json.encode(tokenValidation));
    }
    
    dynamic userId = ObjectId.fromHexString(request.params['id'].toString());
    final usersDelete = await UsersRepository.delete({"_id":userId});
    if (usersDelete == null) {
      return Response.ok('No se ha encontrado ningún usuario con ese id');
    } else {
        final usersGet = await UsersRepository.findOne({"_id":userId});
            if (usersGet == null) {
              return Response.ok('Se ha borrado el usuario correctamente');
            } else {
        return Response.ok('No se ha podido borrar el usuario');
        }
    }

  


}

Map<String, dynamic> validateToken(Request request) {
    final dynamic token =
      request.headers.containsKey("token") ? request.headers["token"] : "";
  final Map<String, dynamic> verifiedToken =
      jwt_service.UserTokenService.verifyJwt(token);
  return verifiedToken;
}


Future<bool> areCredencialValid(Map<String, dynamic> credentials) async {
  final user = await UsersRepository.findOne({"email": credentials["email"]});
  if (user != null) {
    final encriptedPass =
        encrypter.checkPassword(credentials["password"], user["password"]);
    return encriptedPass;
  } else {
    return false;
  }
}


Future<Response> _loginHanler(Request request) async {
  final credentialRequestBody = await request.readAsString();
  final Map<String, dynamic> bodyParams = json.decode(credentialRequestBody);
  // Vericamos que las credenciales vengan el body de la petición
  final String email =
      bodyParams.containsKey('email') ? bodyParams['email'] : '';
  final String password =
      bodyParams.containsKey('password') ? bodyParams['password'] : '';

  // Creamos las credenciales con la contraseña cifrada porque en la base de datos se almacena cifrada
  final Map<String, dynamic> credentials = {
    "email": email,
    "password": password
  };

  final autorizedUser = await areCredencialValid(credentials);

  if (!autorizedUser) {
    return Response.unauthorized(json.encode({
      "message": "Usuario autorizado o las credenciales son inválida",
      "authenticated": false
    }));
  } else {
    String token = jwt_service.UserTokenService.generateJwt({"email": email});
    return Response.ok(json.encode({
      "message": "Usuario autorizado",
      "authenticated": true,
      "token": token
    }));
  }
}




