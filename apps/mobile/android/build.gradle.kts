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

// flutter_plugin_android_lifecycle requires compileSdk 36 while some plugin
// modules (file_picker) still pin 34. Raise every plugin module to 36 —
// compileSdk only changes what they compile against, not runtime behaviour.
// evaluationDependsOn(":app") above may have evaluated a project already, so
// bump immediately in that case instead of registering afterEvaluate.
subprojects {
    fun bumpCompileSdk(project: Project) {
        project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            if (compileSdkVersion?.removePrefix("android-")?.toIntOrNull()?.let { it < 36 } == true) {
                compileSdkVersion(36)
            }
        }
    }
    if (state.executed) bumpCompileSdk(this) else afterEvaluate { bumpCompileSdk(this) }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
