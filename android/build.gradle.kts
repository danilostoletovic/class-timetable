allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (project.name != "app") {
        val setSdk: () -> Unit = {
            if (project.hasProperty("android")) {
                val androidExt = project.extensions.findByName("android")
                if (androidExt != null) {
                    val cls = androidExt.javaClass
                    val methods = listOf(
                        Pair("compileSdkVersion", Int::class.javaPrimitiveType),
                        Pair("setCompileSdkVersion", Int::class.javaPrimitiveType),
                        Pair("setCompileSdk", java.lang.Integer::class.java),
                        Pair("setCompileSdk", Int::class.javaPrimitiveType)
                    )
                    for ((name, paramType) in methods) {
                        try {
                            val m = cls.getMethod(name, paramType)
                            m.invoke(androidExt, 36)
                            break
                        } catch (_: Exception) {}
                    }
                }
            }
        }

        if (project.state.executed) {
            setSdk()
        } else {
            project.afterEvaluate {
                setSdk()
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
