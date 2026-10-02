<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
interface Project { id: string; repo: string; stars: number; license: string; category: string; summary: string; archived: boolean }
interface Spec { parameters: string[]; artifactType: string; ecosystem: string; prompt: string }
interface Recipe { id: string; projectId: string; name: string; category: string; spec: Spec; verification: string }
interface Release { id: number; recipeId: string; slug: string; version: string; status: string; sha256: string; fileId: string; skillId: number; content: string }
const projects = ref<Project[]>([]), recipes = ref<Recipe[]>([]), releases = ref<Release[]>([]);
const query = ref(''), category = ref(''), stars = ref(0), mode = ref('cards'), tab = ref('catalog');
const selected = ref<Project | null>(null), recipe = ref<Recipe | null>(null);
const busy = ref(false), error = ref(''), notice = ref(''), shellOrigin = ref('');
const operatorKey = ref(''), parameters = ref<Record<string, string>>({}), output = ref(''), download = ref('');
const pendingRun = ref('');
const deviceId = ref('');
const executionPlace = ref('server');
const reviewNote = ref(''), draftVersion = ref('0.1.0'), draftContent = ref(''), importQuery = ref('stars:>=10000 topic:agent-skills');
const audit = ref<unknown>(null);
const categories: Record<string, string> = { document: '📊 文档', image: '🎨 图片', video: '🎬 视频', code: '💻 代码' };
const states: Record<string, string> = { unverified: '未验证', verified: '已验证', pending_channel: '待渠道', draft: '草稿', review: '待审核', approved: '审核通过', rejected: '已驳回', published: '已发布' };
const visibleProjects = computed(() => projects.value.filter(p => (!category.value || p.category === category.value || recipes.value.some(r => r.projectId === p.id && r.category === category.value)) && p.stars >= stars.value && `${p.repo} ${p.summary}`.toLowerCase().includes(query.value.toLowerCase())));
const visibleRecipes = computed(() => recipes.value.filter(r => (!category.value || r.category === category.value) && `${r.name} ${r.spec.ecosystem}`.toLowerCase().includes(query.value.toLowerCase())));
const projectRecipes = computed(() => recipes.value.filter(r => r.projectId === selected.value?.id));
const recipeReleases = computed(() => releases.value.filter(r => r.recipeId === recipe.value?.id));
async function api<T>(path: string, body?: unknown, method = body === undefined ? 'GET' : 'POST'): Promise<T> {
 const headers: Record<string, string> = { 'Content-Type': 'application/json' };
 if (operatorKey.value) headers.Authorization = `Bearer ${operatorKey.value}`;
 const response = await fetch(`/api${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
 const result = await response.json();
 if (!response.ok) throw new Error(result.error === 'operator_required' ? '需要审核员密钥；密钥仅保留在当前页面内存中。' : result.error || `请求失败 (${response.status})`);
 return result as T;
}
async function action(fn: () => Promise<void>) { busy.value = true; error.value = ''; notice.value = ''; try { await fn(); } catch (e) { error.value = e instanceof Error ? e.message : '请求失败'; } finally { busy.value = false; } }
async function reload() { [projects.value, recipes.value, releases.value] = await Promise.all([api<Project[]>('/projects'), api<Recipe[]>('/recipes'), api<Release[]>('/releases')]); }
function openRecipe(r: Recipe) { recipe.value = r; parameters.value = Object.fromEntries(r.spec.parameters.map(k => [k, ''])); output.value = ''; download.value = ''; pendingRun.value = ''; draftContent.value = `# ${r.name}\n\n${r.spec.prompt}\n\n云端配方通过 Skill Hub 调用配置的 toolgate 模型。不得在本地启动图片或视频推理。渠道未就绪时停止并明确报告，不能把干跑当作生成成功。`; }
async function dryRun() { if (!recipe.value) return; await action(async () => { output.value = JSON.stringify(await api(`/recipes/${recipe.value!.id}/dry-run`, parameters.value), null, 2); notice.value = '参数校验完成。干跑不会调用模型，也不代表真实运行通过。'; }); }
async function run() { if (!recipe.value) return; await action(async () => { const result = await api<{ downloadUrl?: string; runId: string; status: string }>(`/recipes/${recipe.value!.id}/run`, parameters.value); output.value = JSON.stringify(result, null, 2); download.value = result.downloadUrl ?? ''; pendingRun.value = result.status === 'pending' ? result.runId : ''; await reload(); }); }
async function poll() { await action(async () => { const result = await api<{ downloadUrl?: string; status: string }>(`/runs/${pendingRun.value}/poll`, {}); output.value = JSON.stringify(result, null, 2); download.value = result.downloadUrl ?? ''; if (result.status === 'succeeded') pendingRun.value = ''; await reload(); }); }
async function launch(release: Release) { await action(async () => { const result = await api<{ url: string }>(`/releases/${release.id}/launch`, parameters.value); const url = new URL(result.url); if (url.origin !== shellOrigin.value || url.protocol !== 'https:') throw new Error('运行入口来源不匹配'); if (executionPlace.value === 'pc') { if (!/^[A-Za-z0-9_-]{1,64}$/.test(deviceId.value.trim())) throw new Error('请填写已绑定 PC 的设备编号'); url.searchParams.set('device', deviceId.value.trim()); url.searchParams.set('backend', 'codex'); } window.location.assign(url.href); }); }
async function review(release: Release, decision: string) { await action(async () => { await api(`/releases/${release.id}/review`, { decision, note: reviewNote.value }); await reload(); notice.value = '审核记录已保存'; }); }
async function publish(release: Release) { await action(async () => { await api(`/releases/${release.id}/publish`, {}); await reload(); notice.value = '已通过 core 上传 API 发布'; }); }
async function createRelease() { if (!recipe.value) return; await action(async () => { await api('/releases', { recipeId: recipe.value!.id, version: draftVersion.value, content: draftContent.value }); await reload(); notice.value = '不可变草稿版本已创建，须提交审核后才能发布。'; }); }
async function importDraft() { await action(async () => { const result = await api<{ draft: string }>('/imports', { query: importQuery.value }); draftContent.value = result.draft; output.value = result.draft; notice.value = '转译草稿已生成。请检查内容，再为相应配方创建版本。'; }); }
onMounted(() => { void action(async () => { const config = await api<{ shellOrigin: string }>('/config'); shellOrigin.value = config.shellOrigin; await reload(); }); });
</script>
<template>
 <div class="workspace">
  <aside class="rail">
   <a class="brand" href="/" aria-label="Skill Hub 首页"><span class="mark">S</span><span>Skill Hub<small>独立技能目录</small></span></a>
   <nav aria-label="主要导航"><button :class="{ active: tab === 'catalog' }" @click="tab = 'catalog'">项目目录 <span>{{ projects.length }}</span></button><button :class="{ active: tab === 'recipes' }" @click="tab = 'recipes'">运行配方 <span>{{ recipes.length }}</span></button><button :class="{ active: tab === 'review' }" @click="tab = 'review'">审核工作台</button></nav>
   <div class="rail-note"><span class="dot"></span> 独立服务<br><p>发现项目，审核配方，<br>在 nucleagent 中继续。</p><a v-if="shellOrigin" :href="shellOrigin">返回 nucleagent ↗</a><p v-if="shellOrigin"><a :href="`${shellOrigin}/deliverables`">查看任务产物 ↗</a></p></div>
  </aside>
  <main>
   <header class="topbar"><span>工作空间 / {{ tab === 'catalog' ? '项目目录' : tab === 'recipes' ? '运行配方' : '审核工作台' }}</span><span class="quiet">来源快照 · 2026.10.01</span></header>
   <div class="page">
    <p class="eyebrow">SKILLS / RECIPES / ARTIFACTS</p>
    <h1>{{ tab === 'catalog' ? '找到下一项能力。' : tab === 'recipes' ? '从想法，到可复用的产物。' : '让每次发布有据可查。' }}</h1>
    <p class="intro">{{ tab === 'review' ? '候选内容先成为草稿。人工审核通过后，才能安装为不可变版本。' : '浏览有来源的开源项目，选择文档、图片与视频配方。运行结果与渠道状态如实记录。' }}</p>
    <p v-if="error" role="alert" class="alert error">{{ error }}</p><p v-if="notice" role="status" class="alert">{{ notice }}</p>
    <div v-if="tab !== 'review'" class="toolbar">
     <label class="search"><span class="sr-only">搜索项目或配方</span><input v-model="query" placeholder="搜索项目、能力或配方…" type="search"></label>
     <label><span class="sr-only">最低 stars</span><select v-model="stars"><option :value="0">全部 stars</option><option :value="10000">10k+</option><option :value="30000">30k+</option><option :value="100000">100k+</option></select></label>
     <button :aria-pressed="mode === 'list'" @click="mode = mode === 'cards' ? 'list' : 'cards'">{{ mode === 'cards' ? '列表视图' : '卡片视图' }}</button>
    </div>
    <div v-if="tab !== 'review'" class="filters" aria-label="类别筛选"><button :class="{ selected: !category }" @click="category = ''">全部</button><button v-for="(label, key) in categories" :key="key" :class="{ selected: category === key }" @click="category = key">{{ label }}</button></div>
    <template v-if="tab === 'catalog'">
     <div class="section-line"><h2>精选项目 <span>{{ visibleProjects.length }}</span></h2><span>stars 为来源仓库快照，非运行质量评分</span></div>
     <div :class="['catalog', mode]">
      <article v-for="p in visibleProjects" :key="p.id" class="project-card"><div class="card-top"><span class="repo-icon">{{ p.repo.split('/')[1].slice(0, 2).toUpperCase() }}</span><span class="stars">☆ {{ (p.stars / 1000).toFixed(1) }}k</span></div><button class="title-button" @click="selected = p">{{ p.repo.split('/')[1] }}</button><p class="owner">{{ p.repo.split('/')[0] }}</p><p class="summary">{{ p.summary || '打开项目查看来源与配方。' }}</p><div class="card-bottom"><span>{{ categories[p.category] }}</span><span class="badge">{{ p.archived ? '已归档' : '来源已核实' }}</span></div><span class="license">{{ p.license }}</span></article>
     </div><p v-if="!visibleProjects.length" class="empty">没有符合条件的项目。试试其他类别或关键词。</p>
    </template>
    <template v-else-if="tab === 'recipes'">
     <div class="section-line"><h2>配方 <span>{{ visibleRecipes.length }}</span></h2><span>6 文档 · 4 图片 · 2 视频</span></div>
     <div :class="['catalog', mode]"><article v-for="r in visibleRecipes" :key="r.id" class="project-card"><div class="card-top"><span>{{ categories[r.category] }}</span><span class="badge">{{ states[r.verification] }}</span></div><button class="title-button" @click="openRecipe(r)">{{ r.name }}</button><p class="summary">{{ r.spec.ecosystem }} 生态参考配方</p><p class="quiet">{{ r.category === 'document' ? r.spec.artifactType : 'toolgate 云端模型 · 待渠道验证' }}</p><button class="secondary" @click="openRecipe(r)">查看参数与版本 →</button></article></div>
    </template>
    <section v-else class="review-panel">
     <label>审核员密钥<input v-model="operatorKey" type="password" autocomplete="off" placeholder="从受限部署文件读取，页面刷新后清除"></label>
     <div class="import-row"><label>GitHub 搜索<input v-model="importQuery"></label><button :disabled="busy" @click="importDraft">搜索并转译草稿</button><button :disabled="busy" @click="action(async () => { audit = await api('/audit'); })">查看审计</button></div>
     <p class="quiet">匿名搜索至多每 7 秒一次。转译仅走 toolgate，未经审核不得发布。</p>
     <label>审核意见<textarea v-model="reviewNote" rows="2" placeholder="记录来源、许可、依赖、网络访问和验证结论"></textarea></label>
     <div v-for="release in releases" :key="release.id" class="release-row"><div><strong>{{ release.slug }}</strong><p>{{ states[release.status] }} · {{ release.version }}</p><details><summary>审阅内容和摘要</summary><pre>{{ release.content }}</pre><code>{{ release.sha256 }}</code></details></div><div class="row-actions"><button v-if="release.status === 'draft'" :disabled="busy || !reviewNote" @click="review(release, 'review')">提交审核</button><template v-if="release.status === 'review'"><button :disabled="busy || !reviewNote" @click="review(release, 'approved')">通过</button><button :disabled="busy || !reviewNote" @click="review(release, 'rejected')">驳回</button></template><button v-if="release.status === 'approved'" :disabled="busy" @click="publish(release)">发布并安装</button></div></div>
     <p v-if="!releases.length" class="empty">还没有草稿版本。从“运行配方”中创建第一份草稿。</p><pre v-if="audit">{{ JSON.stringify(audit, null, 2) }}</pre><pre v-if="output">{{ output }}</pre>
    </section>
   </div>
  </main>
  <div v-if="selected" class="overlay" @click.self="selected = null"><section role="dialog" aria-modal="true" aria-label="项目详情" class="detail"><button class="close" aria-label="关闭项目详情" @click="selected = null">×</button><p class="eyebrow">PROJECT / {{ categories[selected.category] }}</p><h2>{{ selected.repo }}</h2><p>{{ selected.summary }}</p><div class="facts"><span>☆ {{ selected.stars.toLocaleString() }}</span><span>{{ selected.license }}</span><a :href="`https://github.com/${selected.repo}`" target="_blank" rel="noopener noreferrer">查看 README ↗</a></div><h3>关联配方</h3><p class="quiet">关联表示可参考的能力方向，不代表安装或运行了上游项目。</p><button v-for="r in projectRecipes" :key="r.id" class="recipe-link" @click="openRecipe(r); selected = null">{{ categories[r.category] }} {{ r.name }} <span>{{ states[r.verification] }} →</span></button><p v-if="!projectRecipes.length" class="empty">当前仅收录来源，尚无受审运行配方。</p></section></div>
  <div v-if="recipe" class="overlay" @click.self="recipe = null"><section role="dialog" aria-modal="true" aria-label="配方详情" class="detail"><button class="close" aria-label="关闭配方详情" @click="recipe = null">×</button><p class="eyebrow">RECIPE / {{ categories[recipe.category] }}</p><h2>{{ recipe.name }}</h2><p>{{ recipe.spec.ecosystem }} · {{ recipe.spec.artifactType }}</p><label v-for="key in recipe.spec.parameters" :key="key">{{ key === 'content' ? '内容或创作要求' : key }}<textarea v-model="parameters[key]" rows="5" maxlength="20000" placeholder="输入本次任务所需内容"></textarea></label><div class="row-actions"><button :disabled="busy" @click="dryRun">校验参数</button><button :disabled="busy || !operatorKey" @click="run">生成产物</button></div><p class="quiet">生成产物需要审核员身份与可用模型渠道。不会在本机运行图像或视频推理。</p><button v-if="pendingRun" :disabled="busy" @click="poll">查询视频进度</button><a v-if="download" :href="download" class="download">下载产物 ↗</a><pre v-if="output">{{ output }}</pre><p v-if="error" role="alert" class="alert error">{{ error }}</p><h3>执行位置</h3><label>运行设备<select v-model="executionPlace"><option value="server">服务器</option><option value="pc">已绑定 PC · Codex</option></select></label><label v-if="executionPlace === 'pc'">设备编号<input v-model="deviceId" maxlength="64" placeholder="从本机面板复制已绑定设备编号"></label><p class="quiet">进入任务页面后选择模型并确认启动。完成后的结果与文件保存在任务记录和成果库。</p><a v-if="shellOrigin" :href="`${shellOrigin}/deliverables`">打开成果库 ↗</a><h3>版本</h3><div v-for="release in recipeReleases" :key="release.id" class="release-row"><div><strong>{{ release.version }}</strong><p>{{ states[release.status] }}</p></div><button v-if="release.status === 'published'" :disabled="busy" @click="launch(release)">在 nucleagent 中运行 ↗</button></div><p v-if="!recipeReleases.length" class="empty">暂无发布版本。审核通过后可在 nucleagent 中运行。</p><details><summary>审核员：创建版本</summary><label>版本号<input v-model="draftVersion" placeholder="0.1.0"></label><label>技能内容<textarea v-model="draftContent" rows="8"></textarea></label><button :disabled="busy || !operatorKey" @click="createRelease">创建不可变草稿</button></details></section></div>
 </div>
</template>
