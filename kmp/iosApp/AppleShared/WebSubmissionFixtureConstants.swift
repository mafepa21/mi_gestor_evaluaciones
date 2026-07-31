// Constantes del fixture de interoperabilidad, generadas desde
// `kmp/iosApp/PlannerTests/Recursos/interop-v1.json` para que el banco de pruebas
// no dependa de leer un fichero del bundle (y por tanto no haya que tocar
// `project.yml`, que chocaria con `develop`).
//
// SOLO DEBUG. La clave privada de aqui es de un solo uso, la genero el repo de la
// PWA para pruebas y no protege ningun dato real.

#if DEBUG
enum WebSubmissionFixture {
    static let formInstanceId = "11111111-1111-4111-8111-111111111111"
    static let submissionId = "22222222-2222-4222-8222-222222222222"
    static let participantAlias = "pkzLJ58Ece2pVl3YgROF5g"
    static let recipientPrivateKeyBase64URL = "Yl5OWNyxcKrQqrtHngc6T1MN3fq72MDV6ZT5X16ERdc"

    static let manifestJSON = #"""
{"schemaVersion":1,"formInstanceId":"11111111-1111-4111-8111-111111111111","title":"Fixture de interoperabilidad","locale":"es","items":[{"webItemId":"f_check","type":"CHECK","title":"Casilla","required":true},{"webItemId":"f_text","type":"TEXT","title":"Texto","required":true,"maxLength":200},{"webItemId":"f_number","type":"NUMBER","title":"Número","required":true,"min":0.5,"max":250},{"webItemId":"f_scale","type":"SCALE_1_4","title":"Escala","required":true,"scaleLabels":["Uno","Dos","Tres","Cuatro"]},{"webItemId":"f_choice","type":"CHOICE","title":"Elección con \"comillas\", barra \\ y salto\nde línea","required":true,"options":["grip","trajectory","timing"]}],"recipientKey":"x25519:u5jJORpkkobdwvA5XXHf9znFHwjETVOinVOQZodKsQ0","publisherKey":"ed25519:X97CWG-iDirOG9phfzXSLY6c219FSN-ztyTscbnLWic","expiresAt":"2030-06-30T23:59:59Z","signature":"zpg_8fQyisXnh_IdM0DNaTdEGmU4mvvQF2eZiMasyN6xnjLh3DrDt7vhNnQCfLhMv7SwLie3yiCsyYjei9QDBA"}
"""#

    static let envelopeJSON = #"""
{"schemaVersion":1,"submissionId":"22222222-2222-4222-8222-222222222222","formInstanceId":"11111111-1111-4111-8111-111111111111","participantAlias":"pkzLJ58Ece2pVl3YgROF5g","clientSubmittedAt":"2026-07-30T09:15:00.000Z","encryptedPayload":"IiVQOVywTI2C5t7K-TfOjpcPH3MSNjUKLqt4Wj6bTWg8BDr6wKBJFoHp0UEWL6GUIVCGvpguMsNl0PoM-J9OZDrMrRaGBlsdqclna7b_dYlMfPZ3R2FVUcQ7BTGcfn-r-3gqpHSvpuACW6m3pgPiQM_AhXcvmi_DR66t-kDkFoHqt1TfgPBq1L7Lu7odGZu85WLAztQdiT9cmbCi6Q21VIXyePd77-JTdY-aTF1JehyulhoD802jslAyavGebOMCaJV-PQOIyqz1En1JZN32L4KSX-rzbfhDb3JCJ1op7ApxMZci9HCOw12tQCqulX05vFeuWwByKj4xfoYcCo657ij6xclnET7wS1rDB5F72F3ogSV-JwqlrNnd038a7ZBrRbB5eykGDnEmKytomfL2PNtYxhxsSPR7pm8vFX9Bv5SOZEqukvkynaqr6UGPDxWuufPsA41eNafSANv8pA","ephemeralPublicKey":"P0PC-955_7Ot1VVYZGUBerXsIy34jBfjxsEAMihF4C0","nonce":"8xsaz-4ZuAfS6VfM"}
"""#
}
#endif
