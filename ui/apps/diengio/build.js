const path = require('path');
const JavaScriptObfuscator = require('javascript-obfuscator');
const { minify } = require('html-minifier-terser');
const CleanCSS = require('clean-css');
const fse = require('fs-extra');

const srcDir = path.join(__dirname, 'src');
const outDir = __dirname;

async function build() {
    try {
        console.log('Bắt đầu quá trình build...');

        // 1. Minify CSS
        console.log('1. Đang tối ưu hoá style.css...');
        const cssContent = fse.readFileSync(path.join(srcDir, 'style.css'), 'utf-8');
        const minifiedCss = new CleanCSS({}).minify(cssContent).styles;
        fse.writeFileSync(path.join(outDir, 'style.css'), minifiedCss);

        // 2. Obfuscate JS
        console.log('2. Đang mã hoá script.js...');
        const jsContent = fse.readFileSync(path.join(srcDir, 'script.js'), 'utf-8');
        const obfuscationResult = JavaScriptObfuscator.obfuscate(jsContent, {
            compact: true,
            controlFlowFlattening: true,
            controlFlowFlatteningThreshold: 0.75,
            deadCodeInjection: true,
            deadCodeInjectionThreshold: 0.4,
            debugProtection: true,
            debugProtectionInterval: 4000,
            disableConsoleOutput: true,
            identifierNamesGenerator: 'hexadecimal',
            log: false,
            numbersToExpressions: true,
            renameGlobals: false,
            selfDefending: true,
            simplify: true,
            splitStrings: true,
            splitStringsChunkLength: 10,
            stringArray: true,
            stringArrayCallsTransform: true,
            stringArrayCallsTransformThreshold: 0.75,
            stringArrayEncoding: ['base64'],
            stringArrayIndexShift: true,
            stringArrayRotate: true,
            stringArrayShuffle: true,
            stringArrayWrappersCount: 2,
            stringArrayWrappersChainedCalls: true,
            stringArrayWrappersParametersMaxCount: 4,
            stringArrayWrappersType: 'function',
            stringArrayThreshold: 0.75,
            transformObjectKeys: true,
            unicodeEscapeSequence: false
        });
        fse.writeFileSync(path.join(outDir, 'script.js'), obfuscationResult.getObfuscatedCode());

        // 3. Minify HTML
        console.log('3. Đang tối ưu hoá index.html...');
        const htmlContent = fse.readFileSync(path.join(srcDir, 'index.html'), 'utf-8');
        const minifiedHtml = await minify(htmlContent, {
            collapseWhitespace: true,
            removeComments: true,
            minifyJS: true,
            minifyCSS: true
        });
        fse.writeFileSync(path.join(outDir, 'index.html'), minifiedHtml);

        // 4. Copy img folder
        console.log('4. Copying thư mục img...');
        fse.copySync(path.join(srcDir, 'img'), path.join(outDir, 'img'), { overwrite: true });

        console.log('✅ Chúc mừng! Quá trình build hoàn tất.');
    } catch (err) {
        console.error('Lỗi trong quá trình build:', err);
    }
}

build();
